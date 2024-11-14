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
!> Kernels for Khairoutdinov-Kogan microphysics.
module bulkmicro_kk
  use modglobal,    only: i1, ih, j1, jh, k1, rlv, cp, pi, rv
  use modmicrodata, only: pirhow, qrmin, Nc_0
  use modprecision, only: field_r
  use modtimer,     only: timer_tic, timer_toc


  implicit none

  private

  real(field_r), parameter :: &
    c_evap = 0.87,  & !< Coefficient for evaporation.
    D0 = 50e-6,     & !< Diameter separating cloud and precipitation parts of the DSD.
    Dv = 2.4e-5,    & !< Diffusivity of water vapor [m2/s].
    Kt = 2.5e-2,    & !< Conductivity of heat [J/(sKm)].
    wfallmax = 9.9, & !< Terminal fall velocity.
    xrmax = 5.2e-7    !< Max mean mass of pw.
  
  public :: do_bulkmicro_kk

contains

  !> Calculate microphysical source terms according to Khairoutdinov and Kogan (2000).
  subroutine do_bulkmicro_kk
    use modmicrodata,     only: qr, Nr, iqr, iNr, thlpmcr, qtpmcr, qcbase, &
                                qcroof, qrbase, qrroof, qcmask, qrmask, qrp, Nrp, &
                                Dvr, xr, delt, precep
    use modfields,        only: rhof, ql0, exnf, qvsl, tmp0, esl, svm, qt0
    use modglobal,        only: dzf
    use modbulkmicrostat, only: bulkmicrotend

    call calculate_rain_parameters(Nr, qr, rhof, qrbase, qrroof, qrmask, Dvr, &
                                   xr)
    call bulkmicrotend
    call autoconversion(ql0, rhof, exnf, qcbase, qcroof, qcmask, thlpmcr, &
                        qtpmcr, qrp, Nrp)
    call bulkmicrotend
    call accretion(ql0, qr, exnf, qcbase, qcroof, qcmask, qrbase, qrroof, &
                   qrmask, thlpmcr, qtpmcr, qrp)
    call bulkmicrotend
    call evaporation(ql0, qt0, qvsl, esl, tmp0, svm(:,:,:,iqr), svm(:,:,:,iNr), &
                     Nr, rhof, exnf, qrbase, qrroof, qrmask, Dvr, xr, delt, &
                    thlpmcr, qtpmcr, qrp, Nrp)
    call bulkmicrotend
#ifdef DALES_GPU
    call sedimentation_rain_gpu(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, delt, &
                                Dvr, xr, qrp, Nrp, precep)
#else
    call sedimentation_rain(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, delt, &
                            Dvr, xr, qrp, Nrp, precep)
#endif
    call bulkmicrotend

  end subroutine do_bulkmicro_kk

  !> Calculate rain DSD integral properties and parameters.
  !!
  !! \param nr rain drop number concentration.
  !! \param qr rain water mixing ratio.
  !! \param rhof Density at full levels.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param Dvr Rain water mean diameter.
  !! \param xr Mean mass of rain drops.
  subroutine calculate_rain_parameters(Nr, qr, rhof, qrbase, qrroof, qrmask, &
                                       Dvr, xr)
    real(field_r), intent(in)  :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)  :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)  :: rhof(1:k1)

    integer,       intent(in)  :: qrbase, qrroof
    logical,       intent(in)  :: qrmask(2:i1,2:j1,1:k1)
    
    real(field_r), intent(out) :: xr(2:i1,2:j1,1:k1)
    real(field_r), intent(out) :: Dvr(2:i1,2:j1,1:k1)

    integer :: i, j, k

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_kk/calculate_rain_parameters', 1)

    !$acc parallel loop collapse(3) default(present)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k)) then
            xr(i,j,k) = rhof(k) * qr(i,j,k) / Nr(i,j,k)

            ! to ensure x_pw is within bounds
            xr(i,j,k) = min(xr(i,j,k), xrmax)
            Dvr(i,j,k) = (xr(i,j,k) / pirhow)**(1.0_field_r/3)
          endif
        enddo
      enddo
    enddo

    call timer_toc('bulkmicro_kk/calculate_rain_parameters')

  end subroutine calculate_rain_parameters

  !> Calculate the autoconversion term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param rhof Density at full levels.
  !! \param exnf Exner function at full levels.
  !! \param qcbase Lowest level with cloud.
  !! \param qcroof Highest level with cloud.
  !! \param qcmask Cloud mask.
  !! \param thlpmcr Tendency of $\theta_l$.
  !! \param qtpmcr Tendency of $\q_t$.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  subroutine autoconversion(ql0, rhof, exnf, qcbase, qcroof, qcmask, thlpmcr, &
                            qtpmcr, qrp, Nrp)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)

    integer,       intent(in)    :: qcbase, qcroof
    logical,       intent(in)    :: qcmask(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)

    integer       :: i, j, k
    real(field_r) :: au

    if (qcbase > qcroof) return

    call timer_tic('bulkmicro_kk/autoconversion', 1)

    !$acc parallel loop collapse(3) default(present) private(au)
    do k = qcbase, qcroof
      do j = 2, j1
        do i = 2, i1
           if (qcmask(i,j,k)) then
              au = 1350 * ql0(i,j,k)**(2.47_field_r) &
                   * (Nc_0 / 1E6)**(-1.79_field_r)
              qrp(i,j,k) = qrp(i,j,k) + au
              qtpmcr(i,j,k) = qtpmcr(i,j,k) - au
              thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * au
              Nrp(i,j,k) = Nrp(i,j,k) + au * rhof(k) / (pirhow * D0**3)
           endif
        enddo
      enddo
    enddo

    call timer_toc('bulkmicro_kk/autoconversion')

  end subroutine autoconversion

  !> Calculate the accretion term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param qr Rain water mixing ratio.
  !! \param exnf Exner function at full levels.
  !! \param qcbase Lowest level with cloud.
  !! \param qcroof Highest level with cloud.
  !! \param qcmask Cloud mask.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param thlpmcr Tendency of $\theta_l$.
  !! \param qtpmcr Tendency of total water mixing ratio.
  !! \param qrp Tendency of rain water mixing ratio.
  subroutine accretion(ql0, qr, exnf, qcbase, qcroof, qcmask, qrbase, qrroof, &
                       qrmask, thlpmcr, qtpmcr, qrp)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)

    integer,       intent(in)    :: qcbase, qcroof
    logical,       intent(in)    :: qcmask(2:i1,2:j1,1:k1)
    integer,       intent(in)    :: qrbase, qrroof
    logical,       intent(in)    :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    
    integer       :: i, j, k
    real(field_r) :: ac

    if (max(qrbase, qcbase) > min(qcroof, qcroof)) return

    call timer_tic('bulkmicro_kk/accretion', 1)

    !$acc parallel loop collapse(3) default(present) private(ac)
    do k = max(qrbase, qcbase), min(qcroof, qrroof)
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k) .and. qcmask(i,j,k)) then
            ac = 67 * (ql0(i,j,k) * qr(i,j,k))**1.15_field_r
            qrp(i,j,k) = qrp(i,j,k) + ac
            qtpmcr(i,j,k) = qtpmcr(i,j,k) - ac
            thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * ac
          endif
        enddo
      enddo
    enddo

    call timer_toc('bulkmicro_kk/accretion')

  end subroutine accretion

  !> Calculate the evaporation term.
  !!
  !! \param ql0 Liquid water mixing ratio.
  !! \param qt0 Total water mixing ratio.
  !! \param qvsl 
  !! \param esl 
  !! \param tmp0 Temperature.
  !! \param qrm Rain water mixing ratio at previous time step.
  !! \param Nrm Rain drop number concentration at previous time step.
  !! \param Nr Rain drop number concentration.
  !! \param rhof Density at full levels.
  !! \param exnf Exner function at full levels.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param Dvr Rain water mean diameter.
  !! \param xr Mean mass of rain drops.
  !! \param delt Time step size.
  !! \param thlpmcr Tendency of $\theta_l$.
  !! \param qtpmcr Tendency of total water mixing ratio.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  subroutine evaporation(ql0, qt0, qvsl, esl, tmp0, qrm, Nrm, Nr, rhof, exnf, &
                         qrbase, qrroof, qrmask, Dvr, xr, delt, thlpmcr, &
                         qtpmcr, qrp, Nrp)
    real(field_r), intent(in)    :: ql0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qt0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qvsl(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: esl(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: tmp0(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: qrm(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: Nrm(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: exnf(1:k1)

    integer,       intent(in)    :: qrbase, qrroof
    logical,       intent(in)    :: qrmask(2:i1,2:j1,1:k1)
    
    real(field_r), intent(in)    :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: xr(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: thlpmcr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: qtpmcr(2-ih:i1+ih,2-jh:j1+jh,1:k1)
    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)

    integer       :: i, j, k
    real(field_r) :: S, G
    real(field_r) :: evap, Nevap

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_kk/evaporation', 1)

    !$acc parallel loop collapse(3) default(present) private(S, G, evap, Nevap)
    do k = qrbase, qrroof
      do j = 2, j1
        do i = 2, i1
          if (qrmask(i,j,k)) then
            S = min(0.0_field_r, (qt0(i,j,k) - ql0(i,j,k)) / qvsl(i,j,k) - 1)
            G = (Rv * tmp0(i,j,k)) / (Dv * esl(i,j,k)) + rlv / &
                (Kt * tmp0(i,j,k)) * (rlv / (Rv * tmp0(i,j,k)) - 1)
            G = 1 / G

            evap = c_evap * 2 * pi * Dvr(i,j,k) * G * S * Nr(i,j,k) / rhof(k)
            Nevap = evap * rhof(k) / xr(i,j,k)

            if (evap < - qrm(i,j,k) / delt) then
              Nevap = - Nrm(i,j,k) / delt
              evap  = - qrm(i,j,k) / delt
            endif

            qrp(i,j,k) = qrp(i,j,k) + evap
            Nrp(i,j,k) = Nrp(i,j,k) + Nevap

            qtpmcr(i,j,k) = qtpmcr(i,j,k) - evap
            thlpmcr(i,j,k) = thlpmcr(i,j,k) + (rlv / (cp * exnf(k))) * evap
          endif
        enddo
      enddo
    enddo

    call timer_toc('bulkmicro_kk/evaporation')

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
  !! \param delt Time step size.
  !! \param Dvr Rain water mean diameter.
  !! \param xr Mean mass of rain drops.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  !! \param precep Precipitation.
  subroutine sedimentation_rain(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, &
                                delt, Dvr, xr, qrp, Nrp, precep)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: dzf(1:k1)

    integer,       intent(inout) :: qrbase
    integer,       intent(in)    :: qrroof
    logical,       intent(inout) :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: xr(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)
    real(field_r), intent(out)   :: precep(2:i1,2:j1,1:k1)

    integer       :: i, j, k, jn
    integer       :: n_spl      !<  sedimentation time splitting loop
    real(field_r) :: sed_qr
    real(field_r) :: sed_Nr

    real(field_r), allocatable :: qr_spl(:,:,:), Nr_spl(:,:,:)

    real(field_r) :: dt_spl

    precep(:,:,:) = 0 ! zero the precipitation flux field
                      ! the update below is not always performed

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_kk/sedimentation_rain', 1)

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

        call calculate_rain_parameters(Nr_spl, qr_spl, rhof, qrbase, qrroof, qrmask, Dvr, xr)
      end if

      do k = qrbase, qrroof
        do j = 2, j1
          do i = 2, i1
            if (qrmask(i,j,k)) then
              sed_qr = max(0.0_field_r, 0.006_field_r * 1E6_field_r * Dvr(i,j,k) - 0.2_field_r) * qr_spl(i,j,k) * rhof(k)
              sed_Nr = max(0.0_field_r, 0.0035_field_r * 1E6_field_r * Dvr(i,j,k) - 0.1_field_r) * Nr_spl(i,j,k)

              qr_spl(i,j,k) = qr_spl(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
              Nr_spl(i,j,k) = Nr_spl(i,j,k) - sed_Nr * dt_spl / dzf(k)

              if (k > 1) then
                qr_spl(i,j,k-1) = qr_spl(i,j,k-1) + sed_qr * dt_spl / (dzf(k-1) * rhof(k-1))
                Nr_spl(i,j,k-1) = Nr_spl(i,j,k-1) + sed_Nr * dt_spl / dzf(k-1)
              endif
              if (jn==1) then
                precep(i,j,k) = sed_qr / rhof(k)   ! kg kg-1 m s-1
              endif
            endif
          enddo
        enddo
      enddo    
    end do ! time splitting loop

    ! the last time splitting step lowered the base level
    ! and we still need to adjust for it
    qrbase = max(1, qrbase - 1)

    Nrp(:,:,qrbase:qrroof) = Nrp(:,:,qrbase:qrroof) + &
      (Nr_spl(:,:,qrbase:qrroof) - Nr(:,:,qrbase:qrroof))/delt

    qrp(:,:,qrbase:qrroof) = qrp(:,:,qrbase:qrroof) + &
      (qr_spl(:,:,qrbase:qrroof) - qr(:,:,qrbase:qrroof))/delt

    deallocate(qr_spl, Nr_spl)

    call timer_toc('bulkmicro_kk/sedimentation_rain')

  end subroutine sedimentation_rain

#ifdef DALES_GPU
  !> Calculate the sedimentation term. Optimized for GPU's.
  !!
  !! \param qr Rain water mixing ratio.
  !! \param Nr Rain drop number concentration.
  !! \param rhof Density at full levels.
  !! \param dzf Thickness of vertical levels.
  !! \param qrbase Lowest level with rain.
  !! \param qrroof Highest level with rain.
  !! \param qrmask Rain mask.
  !! \param delt Time step size.
  !! \param Dvr Rain water mean diameter.
  !! \param xr Mean mass of rain drops.
  !! \param qrp Tendency of rain water mixing ratio.
  !! \param Nrp Tendency of rain drop number concentration.
  !! \param precep Precipitation.
  subroutine sedimentation_rain_gpu(qr, Nr, rhof, dzf, qrbase, qrroof, qrmask, &
                                    delt, Dvr, xr, qrp, Nrp, precep)
    real(field_r), intent(in)    :: qr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: Nr(2:i1,2:j1,1:k1)
    real(field_r), intent(in)    :: rhof(1:k1)
    real(field_r), intent(in)    :: dzf(1:k1)

    integer,       intent(inout) :: qrbase
    integer,       intent(in)    :: qrroof
    logical,       intent(inout) :: qrmask(2:i1,2:j1,1:k1)

    real(field_r), intent(in)    :: delt

    real(field_r), intent(inout) :: Dvr(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: xr(2:i1,2:j1,1:k1)

    real(field_r), intent(inout) :: qrp(2:i1,2:j1,1:k1)
    real(field_r), intent(inout) :: Nrp(2:i1,2:j1,1:k1)
    real(field_r), intent(out)   :: precep(2:i1,2:j1,1:k1)

    integer       :: i, j, k, jn, sedimbase
    integer       :: n_spl      !<  sedimentation time splitting loop
    real(field_r) :: sed_qr
    real(field_r) :: sed_Nr
    real(field_r) :: dt_spl
    real(field_r) :: delt_inv

    real(field_r), allocatable :: qr_spl(:,:,:), Nr_spl(:,:,:)
    real(field_r), allocatable :: qr_tmp(:,:,:), Nr_tmp(:,:,:)

    !$acc parallel loop collapse(3) default(present)
    do k = 1, k1
      do j = 2, j1
        do i = 2, i1
          precep(i,j,k) = 0.0
        end do
      end do
    end do

    if (qrbase > qrroof) return

    call timer_tic('bulkmicro_kk/sedimentation_rain', 1)

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

        call calculate_rain_parameters(Nr_spl, qr_spl, rhof, qrbase, qrroof, qrmask, Dvr, xr)
      end if

      ! Compute precep
      if (jn == 1) then
        !$acc parallel loop collapse(3) default(present)
        do k = qrbase, qrroof
          do j = 2, j1
            do i = 2, i1
              if (qrmask(i,j,k)) then
                precep(i,j,k) = max(0.0_field_r, 0.006_field_r * 1E6_field_r * Dvr(i,j,k) - 0.2_field_r) * qr_spl(i,j,k)
              endif
            enddo
          enddo
        enddo
      end if ! jn == 1

      sedimbase = qrbase

      ! k qrbase if == 1
      if (qrbase == 1) then
        sedimbase = sedimbase + 1
        k = 1

        !$acc parallel loop collapse(2) default(present) private(sed_qr, sed_Nr)
        do j = 2, j1
          do i = 2, i1
            if (qrmask(i,j,k)) then
              sed_qr = max(0.0_field_r, 0.006_field_r *1E6_field_r * Dvr(i,j,k) - 0.2_field_r) * qr_spl(i,j,k) * rhof(k)
              sed_Nr = max(0.0_field_r, 0.0035_field_r *1E6_field_r * Dvr(i,j,k) - 0.1_field_r) * Nr_spl(i,j,k)

              qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr * dt_spl / (dzf(k) * rhof(k))
              Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr * dt_spl / dzf(k)
            endif
          enddo
        enddo
      end if ! qrbase == 1

      !$acc parallel loop collapse(3) default(present) private(sed_qr, sed_Nr)
      do k = sedimbase, qrroof
        do j = 2, j1
          do i = 2, i1
            if (qrmask(i,j,k)) then
              sed_qr = max(0.0_field_r, 0.006_field_r *1E6_field_r * Dvr(i,j,k) - 0.2_field_r) * qr_spl(i,j,k) * rhof(k)
              sed_Nr = max(0.0_field_r, 0.0035_field_r *1E6_field_r * Dvr(i,j,k) - 0.1_field_r) * Nr_spl(i,j,k)

              !$acc atomic update
              qr_tmp(i,j,k) = qr_tmp(i,j,k) - sed_qr*dt_spl/(dzf(k)*rhof(k))
              !$acc atomic update
              Nr_tmp(i,j,k) = Nr_tmp(i,j,k) - sed_Nr*dt_spl/dzf(k)

              !$acc atomic update
              qr_tmp(i,j,k-1) = qr_tmp(i,j,k-1) + sed_qr*dt_spl/(dzf(k-1)*rhof(k-1))
              !$acc atomic update
              Nr_tmp(i,j,k-1) = Nr_tmp(i,j,k-1) + sed_Nr*dt_spl/dzf(k-1)
            endif
          enddo
        enddo
      enddo
    end do ! time splitting loop

    ! the last time splitting step lowered the base level
    ! and we still need to adjust for it
    qrbase = max(1, qrbase - 1)

    delt_inv = 1 / delt

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

    call timer_toc('bulkmicro_kk/sedimentation_rain')

  end subroutine sedimentation_rain_gpu
#endif

end module bulkmicro_kk
