!  This file is part of DALES.
!
! DALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! DALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
!  Copyright 1993-2024 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!
!> Kernels for Seifert-Beheng microphysics
module bulkmicro_sb
  use modglobal,    only: ih, jh, i1, j1, k1, nsv, rlv, cp, eps1, pi, rv, &
                          mygamma21, mygamma251
  use modmicrodata, only: Nc_0, pirhow, qrmin, iqr, inr, rhow
  use modprecision, only: field_r
  use modtimer,     only: timer_tic, timer_toc

  implicit none

  private

  ! Constants
  ! TODO, maybe read these from a namelist.
  real(field_r), parameter :: &
    a_tvsb = 9.65,    & !< Coefficient in terminal velocity param.
    avf = 0.78,       & !< Constant in ventilation factor.
    b_tvsb = 9.8,     & !< Coefficient in terminal velocity param.
    bvf = 0.308,      & !< Constant in ventilation factor.
    c_Nevap = 0.7,    & !< Coefficient for evaporation.
    c_tvsb = 600.,    & !< Coefficient in terminal velocity param.
    D_eq = 1.1e-3,    & !< Parameter for break-up.
    Dv = 2.4e-5,      & !< Diffusivity of water vapor [m^2/s].
    Dvcmax = 79.2e-6, & !< Max mean diameter of cw.
    D_s = Dvcmax,     & !< Diameter separating the cloud and precipitation parts of the DSD.
    k_1 = 4.0e2,      & !< k_1 + k_2: coefficient for phi function in autoconversion rate SB2006.
    k_2 = 0.7,        & !< See k_1.
    kappa_r = 60.7,   & !< See eq. 11 in SB2006.
    k_br = 1000.,     & !< Parameter for break-up.
    k_c = 10.58e9,    & !< Long Kernel coefficient SB2006 (k'cc).
    k_l = 5.e-5,      & !< Coefficient for phi function in accretion rate.
    k_r = 5.25,       & !< Kernel SB2006.
    k_rr = 7.12,      & !< See eq. 11 in SB2006.
    Kt = 2.5e-2,      & !< Conductivity of heat [J/(sKm)].
    nu_a = 1.41e-5,   & !< Kinematic viscosity of air.
    Sc_num = 0.71,    & !< Schmidt number.
    sig_gr = 1.5,     & !< GSD of rain drop DSD.
    wfallmax = 9.9,   & !< Terminal velocity (?)
    xcmin = 4.2e-15,  & !< Min mean mass of cw (D = 2.0e-6 m).
    xcmax = 2.6e-10,  & !< Max mean mass of cw.
    xrmin = xcmax,    & !< Min mean mass of pw.
    xrmax = 5.0e-6,   & !< Max mean maxx of pw.
    x_s = xcmax         !< Drop mass separating the cloud and precipitation parts of the DSD.

  ! Procedures
  public :: do_bulkmicro_sb

contains

  subroutine do_bulkmicro_sb
    use modmicrodata,     only: qr, Nr, iqr, iNr, thlpmcr, qtpmcr, qcbase, &
                                qcroof, qrbase, qrroof, qcmask, qrmask, qrp, Nrp, &
                                Dvr, xr, lbdr, mur, delt, l_lognormal, l_mur_cst, &
                                mur_cst, precep
    use modfields,        only: rhof, ql0, exnf, qvsl, tmp0, esl, svm, qt0
    use modglobal,        only: dzf
    use modbulkmicrostat, only: bulkmicrotend

    call calculate_rain_parameters(Nr, qr, rhof, l_mur_cst, mur_cst, qrbase, &
                                   qrroof, qrmask, xr, Dvr, mur, lbdr)
    call bulkmicrotend
    call autoconversion(ql0, qr, exnf, rhof, qcbase, qcroof, qcmask, thlpmcr, &
                        qtpmcr, qrp, Nrp)
    call bulkmicrotend
    call accretion(ql0, qr, Nr, exnf, rhof, qcbase, qcroof, qrbase, qrroof, &
                   qcmask, qrmask, Dvr, lbdr, thlpmcr, qtpmcr, qrp, Nrp)
    call bulkmicrotend
    call evaporation(ql0, qt0, svm(:,:,:,iqr), svm(:,:,:,inr), qvsl, tmp0, &
                     esl, exnf, rhof, Nr, qrbase, qrroof, qrmask, Dvr, lbdr, &
                     mur, xr, qrp, Nrp, delt, qtpmcr, thlpmcr)
    call bulkmicrotend
#ifdef DALES_GPU
    call sedimentation_rain_gpu(qr, Nr, rhof, dzf, qrbase, qrroof, Dvr, lbdr, &
                                mur, delt, xr, l_lognormal, l_mur_cst, &
                                mur_cst, qrp, Nrp, qrmask, precep)
#else
    call sedimentation_rain(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, &
                            l_lognormal, l_mur_cst, mur_cst, delt, Dvr, lbdr, &
                            mur, xr, qrp, Nrp, precep)
#endif
    call bulkmicrotend

  end subroutine do_bulkmicro_sb

  !> Calculate rain DSD integral properties and parameters.
  !!
  !! \param nr rain drop number concentration.
  !! \param qr rain water mixing ratio.
  !! \param rhof Density at full levels.
  !! \param l_mur_cst Switch for selecting constant $\mu$.
  !! \param mur_cst Constant $\mu$ value.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param xr Mean mass of rain drops.
  !! \param Dvr Rain water mean diameter.
  !! \param mur DSD $\mu$ parameter.
  !! \param lbdr DSD $\lambda$ parameter.
  subroutine calculate_rain_parameters(Nr, qr, rhof, l_mur_cst, mur_cst, qrbase, &
                                       qrroof, qrmask, xr, Dvr, mur, lbdr)
    real(field_r), intent(in)  :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)  :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)  :: rhof(1:k1)

    logical,       intent(in)  :: l_mur_cst
    real(field_r), intent(in)  :: mur_cst

    integer,       intent(in)  :: qrbase, qrroof
    logical,       intent(in)  :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(out) :: xr(2:i1,2:j1,1:k1)
    real(field_r), intent(out) :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(out) :: mur(2:i1,2:j1,1:k1)
    real(field_r), intent(out) :: lbdr(2:i1,2:j1,1:k1)

    integer       :: i, j, k

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_sb/calculate_rain_parameters', 1)

    if (l_mur_cst) then
      !$acc parallel loop collapse(3) default(present)
      do k = qrbase, qrroof
        do j = 2, j1
          do i = 2, i1
            mur(i,j,k) = mur_cst
          end do
        end do
      end do
    else
      ! mur = f(Dv)
      !$acc parallel loop collapse(3) default(present)
      do k = qrbase, qrroof
        do j = 2, j1
          do i = 2, i1
            if (qrmask(i,j,k)) then
              mur(i,j,k) = min(30.0_field_r, &
                               -1 + 0.008_field_r / (qr(i,j,k) * rhof(k))**0.6_field_r)  ! G09b
            end if
          end do
        end do
      end do
    end if

    !$acc parallel loop collapse(3) default(present)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k)) then
            xr(i,j,k) = rhof(k) * qr(i,j,k) / Nr(i,j,k)

            ! to ensure xr is within bounds
            xr (i,j,k) = min(max(xr(i,j,k), xrmin), xrmax)
            Dvr(i,j,k) = (xr(i,j,k) / pirhow)**(1./3.)
            lbdr(i,j,k) = ((mur(i,j,k) + 3) * (mur(i,j,k) + 2) * (mur(i,j,k) + 1))**(1.0_field_r/3) / Dvr(i,j,k)
          end if
        end do
      end do
    end do

    call timer_toc('bulkmicro_sb/calculate_rain_parameters')

  end subroutine calculate_rain_parameters

  !> Calculate the autoconversion term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param qr Rain water mixing ratio.
  !! \param exnf Exner function at full levels.
  !! \param rhof Density at full levels.
  !! \param qcbase Lowest level with cloud.
  !! \param qcroof Highest level with cloud.
  !! \param qcmask Cloud mask.
  !! \param thlpmcr Tendency of $\theta_l$.
  !! \param qtpmcr Tendency of $\q_t$.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  subroutine autoconversion(ql0, qr, exnf, rhof, qcbase, qcroof, qcmask, thlpmcr, &
                            qtpmcr, qrp, Nrp)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)

    integer,       intent(in)    :: qcbase, qcroof
    logical,       intent(in)    :: qcmask(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)

    integer       :: i, j, k
    real(field_r) :: &
      au,   &
      tau,  & !< internal time scale
      phi,  & !< correction function (see SB2001)
      xc,   & !< mean mass of cloud water droplets
      nuc,  & !< width parameter of cloud DSD
      k_au    !< Coefficient for autoconversion rate

    if (qcbase > qcroof) return

    call timer_tic('bulkmicro_sb/autoconversion', 1)

    k_au = k_c / (20 * x_s)

    !$acc parallel loop collapse(3) default(present)
    do k = qcbase, qcroof
      do j = 2, j1
        do i = 2, i1
           if (qcmask(i,j,k)) then
              nuc = 1.58_field_r * (rhof(k) * ql0(i,j,k) * 1000.0_field_r) &
                    + 0.72_field_r - 1.0_field_r !G09a
              xc = rhof(k) * ql0(i,j,k) / Nc_0 ! No eps0 necessary
              au = k_au * (nuc + 2) * (nuc + 4) / (nuc + 1)**2 &
                        * (ql0(i,j,k) * xc)**2 * 1.225_field_r ! *rho**2/rho/rho (= 1)

              tau = qr(i,j,k) / (ql0(i,j,k) + qr(i,j,k))
              phi = k_1 * tau**k_2 * (1 - tau**k_2)**3
              au = au * (1 + phi / (1 - tau)**2)

              qrp(i,j,k) = qrp(i,j,k) + au
              Nrp(i,j,k) = Nrp(i,j,k) + au / x_s
              qtpmcr(i,j,k) = qtpmcr(i,j,k) - au
              thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * au
           end if
        end do
      end do
    end do

    call timer_toc('bulkmicro_sb/autoconversion')

  end subroutine autoconversion

  !> Calculate the accretion term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param qr Rain water mixing ratio.
  !! \param Nr Rain drop number concentration.
  !! \param exnf Exner function at full levels.
  !! \param rhof Density at full levels.
  !! \param qcbase Lowest level with cloud.
  !! \param qcroof Highest level with cloud.
  !! \param qcmask Cloud mask.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param Dvr Rain water mean diameter.
  !! \param lbdr DSD $\lambda$ parameter.
  !! \param thlpmcr Tendency of $\theta_l$.
  !! \param qtpmcr Tendency of total water mixing ratio.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  subroutine accretion(ql0, qr, Nr, exnf, rhof, qcbase, qcroof, qrbase, qrroof, &
                       qcmask, qrmask, Dvr, lbdr, thlpmcr, qtpmcr, qrp, Nrp)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)

    integer,       intent(in)    :: qcbase, qcroof, qrbase, qrroof
    logical,       intent(in)    :: qcmask(2:i1,2:j1,1:k1)
    logical,       intent(in)    :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: lbdr(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)

    integer :: i,j,k

    real(field_r) :: ac, sc, br
    real(field_r) :: phi     !  correction function (see SB2001)
    real(field_r) :: phi_br
    real(field_r) :: tau     !  internal time scale

    if (max(qrbase, qcbase) > min(qrroof, qcroof)) return

    call timer_tic('bulkmicro_sb/accretion', 1)

    !$acc parallel loop collapse(3) default(present)
    do k = max(qrbase,qcbase), min(qrroof, qcroof)
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k) .and. qcmask(i,j,k)) then
             tau = qr(i,j,k) / (ql0(i,j,k) + qr(i,j,k))
             phi = (tau / (tau + k_l))**4
             ac = k_r * rhof(k) * ql0(i,j,k) * qr(i,j,k) * phi &
                  * (1.225_field_r / rhof(k))**0.5_field_r

             qrp(i,j,k) = qrp(i,j,k) + ac
             qtpmcr(i,j,k) = qtpmcr(i,j,k) - ac
             thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * ac
          end if
        end do
      end do
    end do

    if (qrbase > qrroof) return

    !$acc parallel loop collapse(3) default(present)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k)) then
             sc = k_rr *rhof(k)* qr(i,j,k) * Nr(i,j,k)  &
                  * (1 + kappa_r / lbdr(i,j,k) * pirhow**(1.0_field_r/3))**(-9) &
                  * (1.225_field_r / rhof(k))**0.5_field_r
             if (Dvr(i,j,k) .gt. 0.30E-3_field_r) then
               phi_br = k_br * (Dvr(i,j,k) - D_eq)
               br = (phi_br + 1) * sc
             else
               br = 0
             end if

             Nrp(i,j,k) = Nrp(i,j,k) - sc + br
          end if
        end do
      end do
    end do

    call timer_toc('bulkmicro_sb/accretion')

  end subroutine accretion

  !> Calculate the evaporation term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param qt0 Total water mixing ratio.
  !! \param qrm Rain water mixing ratio at previous time step.
  !! \param Nrm Rain drop number concentration at previous time step.
  !! \param qvsl Saturation humidity over liquid.
  !! \param tmp0 Temperature.
  !! \param esl Saturation vapor pressure over liquid.
  !! \param exnf Exner function at full levels.
  !! \param rhof Density at full levels.
  !! \param Nr Rain drop number concentration.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param Dvr Rain water mean diameter.
  !! \param lbdr DSD $\lambda$ parameter.
  !! \param mur DSD $\mu$ parameter.
  !! \param xr Mean mass of rain drops.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  !! \param delt Time step size.
  !! \param qtpmcr Tendency of total water mixing ratio.
  !! \param thlpmcr Tendency of $\theta_l$.
  subroutine evaporation(ql0, qt0, qrm, Nrm, qvsl, tmp0, esl, exnf, rhof, Nr, qrbase, &
                         qrroof, qrmask, Dvr, lbdr, mur, xr, qrp, Nrp, delt, &
                         qtpmcr, thlpmcr)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qt0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qrm(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: Nrm(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qvsl(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: tmp0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: esl(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)

    integer,       intent(in)    :: qrbase, qrroof
    logical,       intent(in)    :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: lbdr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: mur(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: xr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)

    integer       :: i,j,k
    integer       :: numel
    real(field_r) :: F !< ventilation factor
    real(field_r) :: S !< super or undersaturation
    real(field_r) :: G !< cond/evap rate of a drop
    real(field_r) :: evap, Nevap
    real(field_r) :: mur_, lbdr_

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_sb/evaporation', 1)

    !$acc parallel loop collapse(3) default(present)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k)) then
            mur_ = mur(i,j,k)
            lbdr_ = lbdr(i,j,k)

            numel = nint(mur_ * 100)
            F = avf * mygamma21(numel)*Dvr(i,j,k) +  &
               bvf*Sc_num**(1./3.)*(a_tvsb/nu_a)**0.5*mygamma251(numel)*Dvr(i,j,k)**(3./2.) * &
               (1. - (1.0_field_r/2)   * (b_tvsb / a_tvsb)    *(lbdr_ / (    c_tvsb + lbdr_))**(mur_ + 2.5_field_r) &
                   - (1.0_field_r/8)   * (b_tvsb / a_tvsb)**2 *(lbdr_ / (2 * c_tvsb + lbdr_))**(mur_ + 2.5_field_r) &
                   - (1.0_field_r/16)  * (b_tvsb / a_tvsb)**3 *(lbdr_ / (3 * c_tvsb + lbdr_))**(mur_ + 2.5_field_r) &
                   - (5.0_field_r/128) * (b_tvsb / a_tvsb)**4 *(lbdr_ / (4 * c_tvsb + lbdr_))**(mur_ + 2.5_field_r) )
            S = min(0.0_field_r, (qt0(i,j,k) - ql0(i,j,k)) / qvsl(i,j,k) - 1)
            G = (Rv * tmp0(i,j,k)) / (Dv * esl(i,j,k)) + rlv / (Kt * tmp0(i,j,k)) * (rlv / (Rv * tmp0(i,j,k)) - 1)
            G = 1/G

            evap = 2 * pi * Nr(i,j,k) * G * F * S / rhof(k)
            Nevap = c_Nevap * evap * rhof(k) / xr(i,j,k)
            
            ! TODO: replace svm reference by qr and nr?
            !if (evap < -svm(i,j,k,iqr)/delt) then
            !  Nevap = - svm(i,j,k,inr)/delt
            !  evap  = - svm(i,j,k,iqr)/delt
            !end if
            if (evap < - qrm(i,j,k) / delt) then
              Nevap = - Nrm(i,j,k) / delt
              evap  = - qrm(i,j,k) / delt
            end if

            qrp(i,j,k) = qrp(i,j,k) + evap
            Nrp(i,j,k) = Nrp(i,j,k) + Nevap

            qtpmcr(i,j,k) = qtpmcr(i,j,k) - evap
            thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * evap
          end if
        end do
      end do
    end do

    call timer_toc('bulkmicro_sb/evaporation')

  end subroutine evaporation

  !> Calculate the sedimentation term.
  !!
  !! \param qr Rain water mixing ratio.
  !! \param Nr Rain drop number concentration.
  !! \param rhof Density at full levels.
  !! \param dzf Thickness of vertical levels.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param l_mur_cst Switch for selecting constant $\mu$.
  !! \param mur_cst Constant $\mu$ value.
  !! \param delt Time step size.
  !! \param Dvr Rain water mean diameter.
  !! \param lbdr DSD $\lambda$ parameter.
  !! \param mur DSD $\mu$ parameter.
  !! \param xr Mean mass of rain drops.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  !! \param precep Precipitation.
  subroutine sedimentation_rain(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, &
                                l_lognormal, l_mur_cst, mur_cst, delt, Dvr, lbdr, &
                                mur, xr, qrp, Nrp, precep)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: dzf(1:k1)

    integer,       intent(inout) :: qrbase
    integer,       intent(in)    :: qrroof
    logical,       intent(inout) :: qrmask(2:i1,2:j1,1:k1)

    logical,       intent(in)    :: l_lognormal, l_mur_cst
    real(field_r), intent(in)    :: mur_cst
    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: lbdr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: mur(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: xr(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)
    real(field_r), intent(out)   :: precep(2:i1,2:j1,1:k1)

    integer       :: i, j, k, jn
    integer       :: n_spl      !<  sedimentation time splitting loop
    real(field_r) :: pwcont
    real(field_r) :: Dgr           !<  lognormal geometric diameter
    real(field_r) :: wfall_qr      !<  fall velocity for qr
    real(field_r) :: wfall_Nr      !<  fall velocity for Nr
    real(field_r) :: sed_qr
    real(field_r) :: sed_Nr

    real(field_r), allocatable :: qr_spl(:,:,:), Nr_spl(:,:,:)

    real(field_r) :: dt_spl

    call timer_tic('bulkmicro_sb/sedimentation_rain', 1)

    precep(:,:,:) = 0 ! zero the precipitation flux field
                      ! the update below is not always performed

    if (qrbase > qrroof) return

    allocate(qr_spl(2:i1,2:j1,1:k1))
    allocate(Nr_spl(2:i1,2:j1,1:k1))

    n_spl = ceiling(wfallmax * delt / minval(dzf))
    dt_spl = delt / real(n_spl, kind=field_r)

    do jn = 1, n_spl ! time splitting loop
      if (jn == 1) then
        qr_spl(:,:,:) = qr(:,:,:)
        Nr_spl(:,:,:) = Nr(:,:,:)
      else
        ! update parameters after the first iteration
        ! a new mask
        qrmask(:,:,:) = (qr_spl(:,:,:) > qrmin) .and. (Nr_spl(:,:,:) > 0)

        ! lower the rain base by one level to include the rain fall
        ! from the previous step
        qrbase = max(1, qrbase - 1)

        call calculate_rain_parameters(Nr_spl, qr_spl, rhof, l_mur_cst, mur_cst, &
                                       qrbase, qrroof, qrmask, xr, Dvr, mur, lbdr)
      end if

      if (l_lognormal) then
        do k = qrbase,qrroof
          do j = 2, j1
            do i = 2, i1
              if (qrmask(i,j,k)) then
                ! correction for width of DSD
                Dgr = (exp(4.5_field_r * (log(sig_gr))**2))**(-1.0_field_r/3) &
                      * Dvr(i,j,k)
                sed_qr = sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)
                sed_Nr = 1 / pirhow * sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 0)

                ! correction for the fact that pwcont .ne. qr_spl
                ! actually in this way for every grid box a fall velocity is determined
                pwcont = liq_cont(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)       ! note : kg m-3
                if (pwcont > eps1) then
                  sed_qr = (qr_spl(i,j,k) * rhof(k) / pwcont) * sed_qr
                  ! or:
                  ! qr_spl*(sed_qr/pwcont) = qr_spl*fallvel.
                end if

                qr_spl(i,j,k) = qr_spl(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
                Nr_spl(i,j,k) = Nr_spl(i,j,k) - sed_Nr * dt_spl / dzf(k)

                if (k > 1) then
                  qr_spl(i,j,k-1) = qr_spl(i,j,k-1) + sed_qr * dt_spl / (dzf(k-1) * rhof(k-1))
                  Nr_spl(i,j,k-1) = Nr_spl(i,j,k-1) + sed_Nr * dt_spl / dzf(k-1)
                end if
                if (jn == 1) then
                  precep(i,j,k) = sed_qr / rhof(k)   ! kg kg-1 m s-1
                end if
              end if ! qr_spl threshold statement
            end do
          end do
        end do
      else
        do k = qrbase, qrroof
          do j = 2, j1
            do i = 2, i1
              if (qrmask(i,j,k)) then

                wfall_qr = max(0., (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k)+4))))
                wfall_Nr = max(0., (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k)+1))))

                sed_qr  = wfall_qr * qr_spl(i,j,k) * rhof(k) ! m/s * kg/m3
                sed_Nr  = wfall_Nr * Nr_spl(i,j,k)

                qr_spl(i,j,k) = qr_spl(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
                Nr_spl(i,j,k) = Nr_spl(i,j,k) - sed_Nr * dt_spl / dzf(k)

                if (k .gt. 1) then
                  qr_spl(i,j,k-1) = qr_spl(i,j,k-1) + sed_qr * dt_spl / (dzf(k-1) * rhof(k-1))
                  Nr_spl(i,j,k-1) = Nr_spl(i,j,k-1) + sed_Nr * dt_spl / dzf(k-1)
                end if
                if (jn==1) then
                  precep(i,j,k) = sed_qr / rhof(k)   ! kg kg-1 m s-1
                end if
              end if
            end do
          end do
        end do
      end if ! l_lognormal
    end do ! time splitting loop

    ! the last time splitting step lowered the base level
    ! and we still need to adjust for it
    qrbase = max(1, qrbase - 1)

    Nrp(:,:,qrbase:qrroof) = Nrp(:,:,qrbase:qrroof) + &
      (Nr_spl(:,:,qrbase:qrroof) - Nr(:,:,qrbase:qrroof))/delt

    qrp(:,:,qrbase:qrroof) = qrp(:,:,qrbase:qrroof) + &
      (qr_spl(:,:,qrbase:qrroof) - qr(:,:,qrbase:qrroof))/delt

    deallocate(qr_spl, Nr_spl)

    call timer_toc('bulkmicro_sb/sedimentation_rain')

  end subroutine sedimentation_rain

#ifdef DALES_GPU
  !> Calculate the sedimentation term.
  !!
  !! \param qr Rain water mixing ratio.
  !! \param Nr Rain drop number concentration.
  !! \param rhof Density at full levels.
  !! \param dzf Thickness of vertical levels.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param l_mur_cst Switch for selecting constant $\mu$.
  !! \param mur_cst Constant $\mu$ value.
  !! \param delt Time step size.
  !! \param Dvr Rain water mean diameter.
  !! \param lbdr DSD $\lambda$ parameter.
  !! \param mur DSD $\mu$ parameter.
  !! \param xr Mean mass of rain drops.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  !! \param precep Precipitation.
  subroutine sedimentation_rain_gpu(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, &
                                    l_lognormal, l_mur_cst, mur_cst, delt, Dvr, lbdr, &
                                    mur, xr, qrp, Nrp, precep)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: dzf(1:k1)

    integer,       intent(inout) :: qrbase
    integer,       intent(in)    :: qrroof
    logical,       intent(inout) :: qrmask(2:i1,2:j1,1:k1)

    logical,       intent(in)    :: l_lognormal, l_mur_cst
    real(field_r), intent(in)    :: mur_cst
    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: lbdr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: mur(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: xr(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)
    real(field_r), intent(out)   :: precep(2:i1,2:j1,1:k1)

    integer       :: i, j, k, jn, sedimbase
    integer       :: n_spl      !<  sedimentation time splitting loop
    real(field_r) :: pwcont
    real(field_r) :: delt_inv
    real(field_r) :: Dgr           !<  lognormal geometric diameter
    real(field_r) :: wfall_qr      !<  fall velocity for qr
    real(field_r) :: wfall_Nr      !<  fall velocity for Nr
    real(field_r) :: sed_qr
    real(field_r) :: sed_Nr

    real(field_r), allocatable :: qr_spl(:,:,:), Nr_spl(:,:,:)
    real(field_r), allocatable :: qr_tmp(:,:,:), Nr_tmp(:,:,:)

    real(field_r), save :: dt_spl

    !$acc parallel loop collapse(3) default(present)
    do k = 1, k1
      do j = 2, j1
        do i = 2, i1
          precep(i,j,k) = 0.0
        end do
      end do
    end do

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_sb/sedimentation_rain', 1)

    allocate(qr_spl(2:i1,2:j1,1:k1))
    allocate(Nr_spl(2:i1,2:j1,1:k1))
    allocate(qr_tmp(2:i1,2:j1,1:k1))
    allocate(Nr_tmp(2:i1,2:j1,1:k1))

    !$acc enter data create(qr_spl, Nr_spl, qr_tmp, Nr_tmp)

    n_spl = ceiling(wfallmax * delt / minval(dzf))
    dt_spl = delt / real(n_spl, kind=field_r)

    do jn = 1, n_spl ! time splitting loop
      if (jn == 1) then
        !$acc parallel loop collapse(3) default(present)
        do k = 1, k1
          do j = 2, j1
            do i = 2, i1
              qr_spl(i,j,k) = qr(i,j,k)
              Nr_spl(i,j,k) = Nr(i,j,k)
              qr_tmp(i,j,k) = qr(i,j,k)
              Nr_tmp(i,j,k) = Nr(i,j,k)
            end do
          end do
        end do
      else
        !Copy from tmp into spl
        !$acc parallel loop collapse(3) default(present)
        do k = 1, k1
          do j = 2, j1
            do i = 2, i1
              qr_spl(i,j,k) = qr_tmp(i,j,k)
              Nr_spl(i,j,k) = Nr_tmp(i,j,k)

              ! Update mask
              qrmask(i,j,k) = (qr_spl(i,j,k) > qrmin .and. Nr_spl(i,j,k) > 0.0)
            end do
          end do
        end do

        ! lower the rain base by one level to include the rain fall
        ! from the previous step
        qrbase = max(1, qrbase - 1)

        call calculate_rain_parameters(Nr_spl, qr_spl, rhof, l_mur_cst, mur_cst, &
                                      qrbase, qrroof, qrmask, xr, Dvr, mur, lbdr)
      end if

      ! Compute precep
      if (jn == 1) then
        if (l_lognormal) then
          !$acc parallel loop collapse(3) default(present) private(Dgr)
          do k = qrbase, qrroof
            do j = 2, j1
              do i = 2, i1
                if (qrmask(i,j,k)) then
                  Dgr = (exp(4.5_field_r * (log(sig_gr))**2))**(-1.0_field_r/3) * Dvr(i,j,k)
                  sed_qr = sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)
                  pwcont = liq_cont(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)
                  if (pwcont > eps1) then
                    sed_qr = (qr_spl(i,j,k) * rhof(k) / pwcont) * sed_qr
                  end if
                  precep(i,j,k) = sed_qr / rhof(k)   ! kg kg-1 m s-1
                end if
              end do
            end do
          end do
        else ! l_lognormal
          !$acc parallel loop collapse(3) default(present)
          do k = qrbase, qrroof
            do j = 2, j1
              do i = 2, i1
                if (qrmask(i,j,k)) then
                  wfall_qr = max( &
                    0.0_field_r, &
                    a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k) + 4)) &
                  )
                  sed_qr  = wfall_qr * qr_spl(i,j,k) * rhof(k)
                  precep(i,j,k) = sed_qr / rhof(k)   ! kg kg-1 m s-1
                end if
              end do
            end do
          end do
        end if ! l_lognormal
      end if ! jn == 1

      sedimbase = qrbase

      ! k qrbase if == 1
      if (qrbase == 1) then
        sedimbase = sedimbase + 1
        k = 1
          if (l_lognormal) then
            !$acc parallel loop collapse(2) default(present) private(Dgr)
            do j = 2, j1
              do i = 2, i1
                if (qrmask(i,j,k)) then
                  ! correction for width of DSD
                  Dgr = (exp(4.5_field_r * (log(sig_gr))**2))**(-1.0_field_r/3) * Dvr(i,j,k)
                  sed_qr = sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)
                  sed_Nr = 1.0_field_r / pirhow * sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 0)

                  ! correction for the fact that pwcont .ne. qr_spl
                  ! actually in this way for every grid box a fall velocity is determined
                  pwcont = liq_cont(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)       ! note : kg m-3
                  if (pwcont > eps1) then
                    sed_qr = (qr_spl(i,j,k) * rhof(k) / pwcont) * sed_qr
                    ! or:
                    ! qr_spl*(sed_qr/pwcont) = qr_spl*fallvel.
                  end if

                  qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr*dt_spl / (dzf(k) * rhof(k))
                  Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr*dt_spl / dzf(k)
                end if
              end do
            end do
          else ! l_lognormal
            !$acc parallel loop collapse(2) default(present)
            do j = 2, j1
              do i = 2, i1
                if (qrmask(i,j,k)) then
                  wfall_qr = max(0.0_field_r, (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k) + 4))))
                  wfall_Nr = max(0.0_field_r, (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k) + 1))))

                  sed_qr  = wfall_qr*qr_spl(i,j,k)*rhof(k)
                  sed_Nr  = wfall_Nr*Nr_spl(i,j,k)

                  qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr*dt_spl/(dzf(k)*rhof(k))
                  Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr*dt_spl/dzf(k)
                end if
              end do
            end do
          end if ! l_lognormal
      end if ! qrbase == 1

      if (l_lognormal) then
        !$acc parallel loop collapse(3) default(present) private(Dgr)
        do k = sedimbase, qrroof
          do j = 2, j1
            do i = 2, i1
              if (qrmask(i,j,k)) then
                ! correction for width of DSD
                Dgr = (exp(4.5_field_r * (log(sig_gr))**2))**(-1.0_field_r/3) * Dvr(i,j,k)
                sed_qr = sed_flux(Nr_spl(i,j,k),Dgr,log(sig_gr)**2,D_s,3)
                sed_Nr = 1.0_field_r / pirhow * sed_flux(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 0)

                ! correction for the fact that pwcont .ne. qr_spl
                ! actually in this way for every grid box a fall velocity is determined
                pwcont = liq_cont(Nr_spl(i,j,k), Dgr, log(sig_gr)**2, D_s, 3)       ! note : kg m-3
                if (pwcont > eps1) then
                  sed_qr = (qr_spl(i,j,k) * rhof(k) / pwcont) * sed_qr
                  ! or:
                  ! qr_spl*(sed_qr/pwcont) = qr_spl*fallvel.
                end if

                !$acc atomic update
                qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
                !$acc atomic update
                Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr * dt_spl / dzf(k)

                !$acc atomic update
                qr_tmp(i,j,k-1) = qr_tmp(i,j,k-1) + sed_qr*dt_spl / (dzf(k-1) * rhof(k-1))
                !$acc atomic update
                Nr_tmp(i,j,k-1) = Nr_tmp(i,j,k-1) + sed_Nr*dt_spl / dzf(k-1)
              end if
            end do
          end do
        end do
      else
        !$acc parallel loop collapse(3) default(present)
        do k = sedimbase, qrroof
          do j = 2, j1
            do i = 2, i1
              if (qrmask(i,j,k)) then
                wfall_qr = max(0.0_field_r, (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k) + 4))))
                wfall_Nr = max(0.0_field_r, (a_tvsb - b_tvsb * (1 + c_tvsb / lbdr(i,j,k))**(-1 * (mur(i,j,k) + 1))))

                sed_qr  = wfall_qr * qr_spl(i,j,k) * rhof(k)
                sed_Nr  = wfall_Nr * Nr_spl(i,j,k)

                !$acc atomic update
                qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
                !$acc atomic update
                Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr * dt_spl / dzf(k)

                !$acc atomic update
                qr_tmp(i,j,k-1) = qr_tmp(i,j,k-1) + sed_qr * dt_spl / (dzf(k-1) * rhof(k-1))
                !$acc atomic update
                Nr_tmp(i,j,k-1) = Nr_tmp(i,j,k-1) + sed_Nr * dt_spl / dzf(k-1)
              end if
            end do
          end do
        end do
      end if ! l_lognormal

    end do ! time splitting loop

    ! the last time splitting step lowered the base level
    ! and we still need to adjust for it
    qrbase = max(1,qrbase-1)

    delt_inv = 1.0 / delt

    !$acc parallel loop collapse(3) default(present)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          Nrp(i,j,k) = Nrp(i,j,k) + (Nr_tmp(i,j,k) - Nr(i,j,k)) * delt_inv
          qrp(i,j,k) = qrp(i,j,k) + (qr_tmp(i,j,k) - qr(i,j,k)) * delt_inv
        end do
      end do
    end do

    !$acc exit data delete(qr_spl, Nr_spl, qr_tmp, Nr_tmp)

    deallocate(qr_spl, Nr_spl, qr_tmp, Nr_tmp)

    call timer_toc('bulkmicro_sb/sedimentation_rain')

  end subroutine sedimentation_rain_gpu
#endif

  real function sed_flux(Nin, Din, sig2, Ddiv, nnn)
  !*********************************************************************
  ! Function to calculate numerically the analytical solution of the
  ! sedimentation flux between Dmin and Dmax based on
  ! Feingold et al 1986 eq 17 -20.
  ! fall velocity is determined by alfa* D^beta with alfa+ beta taken as
  ! specified in Rogers and Yau 1989 Note here we work in D and in SI
  ! (in Roger+Yau in cm units + radius)
  ! flux is multiplied outside sed_flux with 1/rho_air to get proper
  ! kg/kg m/s units
  !
  ! M.C. van Zanten    August 2005
  !*********************************************************************

    real(field_r), intent(in) :: Nin, Ddiv
    real(field_r), intent(in) :: Din, sig2
    integer,       intent(in) :: nnn
    !para. def. lognormal DSD (sig2 = ln^2 sigma_g), D sep. droplets from drops
    !,power of of D in integral

    real(field_r), parameter ::   &
      C = rhow*pi/6., &
      D_intmin = 1e-6, &
      D_intmax = 4.3e-3

    real(field_r) :: &
      alfa,        & ! constant in fall velocity relation
      beta,        & ! power in fall vel. rel.
      D_min,       & ! min integration limit
      D_max,       & ! max integration limit
      flux           ![kg m^-2 s^-1]

    flux = 0.0_field_r

    if (Din < Ddiv) then
      alfa = 3.e5*100  ![1/ms]
      beta = 2
      D_min = D_intmin
      D_max = Ddiv
      flux = C*Nin*alfa*erfint(beta,Din,D_min,D_max,sig2,nnn)
    else
      ! fall speed ~ D^2
      alfa = 3.e5*100 ![1/m 1/s]
      beta = 2
      D_min = Ddiv
      D_max = 133e-6
      flux = flux + C*Nin*alfa*erfint(beta,Din,D_min,D_max,sig2,nnn)

      ! fall speed ~ D
      alfa = 4e3     ![1/s]
      beta = 1
      D_min = 133e-6
      D_max = 1.25e-3
      flux = flux + C*Nin*alfa*erfint(beta,Din,D_min,D_max,sig2,nnn)

      ! fall speed ~ sqrt(D)
      alfa = 1.4e3 *0.1  ![m^.5 1/s]
      beta = .5
      D_min = 1.25e-3
      D_max = D_intmax
      flux = flux + C*Nin*alfa*erfint(beta,Din,D_min,D_max,sig2,nnn)
    end if
    sed_flux = flux
  end function sed_flux

  real function liq_cont(Nin,Din,sig2,Ddiv,nnn)
  !*********************************************************************
  ! Function to calculate numerically the analytical solution of the
  ! liq. water content between Dmin and Dmax based on
  ! Feingold et al 1986 eq 17 -20.
  !
  ! M.C. van Zanten    September 2005
  !*********************************************************************
    use modglobal, only : pi,rhow
    implicit none

    real(field_r), intent(in) :: Nin, Ddiv
    real(field_r), intent(in) :: Din, sig2
    integer, intent(in) :: nnn
    !para. def. lognormal DSD (sig2 = ln^2 sigma_g), D sep. droplets from drops
    !,power of of D in integral

    real(field_r), parameter :: beta = 0           &
                      ,C = pi/6.*rhow     &
                      ,D_intmin = 80e-6    &   ! value of start of rain D
                      ,D_intmax = 3e-3         !4.3e-3    !  value is now max value for sqrt fall speed rel.

    real(field_r) ::  D_min        & ! min integration limit
            ,D_max        & ! max integration limit
            ,sn

    sn = sign(0.5_field_r, Din - Ddiv)
    D_min = (0.5 - sn) * D_intmin + (0.5 + sn) * Ddiv
    D_max = (0.5 - sn) * Ddiv     + (0.5 + sn) * D_intmax

    liq_cont = C*Nin*erfint(beta,Din,D_min,D_max,sig2,nnn)
  end function liq_cont

  real function erfint(beta, D, D_min, D_max, sig2,nnn )

  !*********************************************************************
  ! Function to calculate erf(x) approximated by a polynomial as
  ! specified in 7.1.27 in Abramowitz and Stegun
  ! NB phi(x) = 0.5(erf(0.707107*x)+1) but 1 disappears by substraction
  !
  !*********************************************************************
    implicit none
    real(field_r), intent(in) :: beta, D, D_min, D_max, sig2
    integer, intent(in) :: nnn

    real(field_r), parameter :: eps = 1e-10       
    !                  ,a1 = 0.278393    & !a1 till a4 constants in polynomial fit to the error
    !                  ,a2 = 0.230389    & !function 7.1.27 in Abramowitz and Stegun
    !                  ,a3 = 0.000972    &
    !                  ,a4 = 0.078108
    real(field_r) :: nn, ymin, ymax, erfymin, erfymax, D_inv

    D_inv = 1./(eps + D)
    nn = beta + nnn

    ymin = 0.707107*(log(D_min*D_inv) - nn*sig2)/(sqrt(sig2))
    ymax = 0.707107*(log(D_max*D_inv) - nn*sig2)/(sqrt(sig2))

    !erfymin = 1.-1./((1.+a1*abs(ymin) + a2*abs(ymin)**2 + a3*abs(ymin)**3 +a4*abs(ymin)**4)**4)
    !erfymax = 1.-1./((1.+a1*abs(ymax) + a2*abs(ymax)**2 + a3*abs(ymax)**3 +a4*abs(ymax)**4)**4)
    erfymin = erf(abs(ymin))
    erfymax = erf(abs(ymax))

    erfymin = sign(erfymin, ymin)
    erfymax = sign(erfymax, ymax)

    erfint = max(0., D**nn*exp(0.5*nn**2*sig2)*0.5*(erfymax-erfymin))
  end function erfint

end module bulkmicro_sb