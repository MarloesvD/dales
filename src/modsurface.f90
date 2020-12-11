!> \file modsurface.f90
!!  Surface parameterization
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
!  Copyright 1993-2009 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!

!>
!! Surface routine including a land-surface scheme
!>
!! This module provides an interactive surface parameterization
!!
!! \par Revision list
!! \par Chiel van Heerwaarden
!! \todo documentation
!! \todo implement water reservoir at land surface for dew and interception water
!! \todo add moisture transport between soil layers
!! \deprecated Modsurface replaces the old modsurf.f90
!! \todo: implement fRs[t] based on the tiles.
!
!  Note that rootf should add up to 1 over all layers
!
!Able to handle heterogeneous surfaces using the switch lhetero
!In case of heterogeneity an input file is needed
!EXAMPLE of the old surface.inp.xxx for isurf = 3,4 (use switch loldtable for compatibility):

!#Surface input file - the standard land cover should be listed below. It is marked by typenr = 0
!#typenr    name       z0mav  z0hav    thls   ps    ustin  wtsurf  wqsurf  wsvsurf(01)  wsvsurf(02)  wsvsurf(03)  wsvsurf(04)
!    0   "standard  "  0.035  0.035   300.0  1.0e5   0.1    0.15   0.1e-3          1.0          0.0          0.0       0.0005
!    1   "forest    "  0.500  0.500   300.0  1.0e5   0.1    0.15   0.2e-3          1.0          0.0          0.0       0.0005
!    2   "grass     "  0.035  0.035   300.0  1.0e5   0.1    0.30   0.1e-3          1.0          0.0          0.0       0.0005

!EXAMPLE of surface.interactive.inp.xxx for isurf = 1:

!#Surface input file - the standard land cover should be listed below. It is marked by typenr = 0
!#typenr    name       z0mav  z0hav   ps    albedo  tsoil1 tsoil2 tsoil3 tsoil4 tsoildeep phiw1 phiw2 phiw3 phiw4 rootf1 rootf2 rootf3 rootf4 Cskin  lambdaskin  Qnet  cveg  Wlav   rsmin  LAI     gD    wsvsurf(01)  wsvsurf(02)  wsvsurf(03)  wsvsurf(04)
!    0   "standard  "  0.035  0.035  1.0e5   0.20      290    287    285    283       283   0.3   0.3   0.3   0.3   0.35   0.38   0.23   0.04 20000         5.0   450   0.9   0.0     110  4.0     0.            1.0          0.0          0.0       0.0005
!    1   "forest    "  0.500  0.500  1.0e5   0.15      290    287    285    283       283   0.3   0.3   0.3   0.3   0.35   0.38   0.23   0.04 20000         5.0   450   0.9   0.0     110  6.0     0.            1.0          0.0          0.0       0.0005
!    2   "grass     "  0.035  0.035  1.0e5   0.25      290    287    285    283       283   0.3   0.3   0.3   0.3   0.35   0.38   0.23   0.04 20000         5.0   450   0.9   0.0     110  2.0     0.            1.0          0.0          0.0       0.0005

!EXAMPLE of surface.prescribed.inp.xxx for isurf = 2,3,4:

!#Surface input file - the standard land cover should be listed below. It is marked by typenr = 0
!#typenr    name       z0mav  z0hav    thls   ps    albedo  rsi_s2  ustin  wtsurf  wqsurf  wsvsurf(01)  wsvsurf(02)  wsvsurf(03)  wsvsurf(04)
!    0   "standard  "  0.035  0.035   300.0  1.0e5   0.20     50.0   0.1    0.15   0.1e-3          1.0          0.0          0.0       0.0005
!    1   "forest    "  0.500  0.500   300.0  1.0e5   0.15     50.0   0.1    0.15   0.2e-3          1.0          0.0          0.0       0.0005
!    2   "grass     "  0.035  0.035   300.0  1.0e5   0.25     50.0   0.1    0.30   0.1e-3          1.0          0.0          0.0       0.0005


module modsurface
  use modsurfdata
  implicit none
  !public  :: initsurface, surface, exitsurface

save

contains
!> Reads the namelists and initialises the soil.
  subroutine initsurface

    use modglobal,  only : i1, j1, i2, j2, itot, jtot, nsv, ifnamopt, fname_options, ifinput, cexpnr
    use modraddata, only : iradiation,rad_shortw,irad_par,irad_user,irad_rrtmg,albedo_rad
    use modmpi,     only : myid, comm3d, mpierr, my_real, mpi_logical, mpi_integer

    implicit none

    integer   :: i,j,k, landindex, ierr, defined_landtypes, landtype_0 = -1
    integer   :: tempx,tempy
 character(len=1500) :: readbuffer
    namelist/NAMSURFACE/ & !< Soil related variables
      isurf,tsoilav, tsoildeepav, phiwav, rootfav, &
      ! Land surface related variables
      lmostlocal, lsmoothflux, lneutral, z0mav, z0hav, rsisurf2, Cskinav, lambdaskinav, albedoav_surf, Qnetav, cvegav, Wlav, &
      ! Jarvis-Steward related variables
      rsminav, rssoilminav, LAI_surfav, gDav, &
      ! Prescribed values for isurf 2, 3, 4
      z0, thls, ps, ustin, wtsurf, wqsurf, wsvsurf, &
      ! Heterogeneous variables
      lhetero, xpatches, ypatches, land_use, loldtable, &
      ! AGS variables
      lrsAgs, lCO2Ags,planttype, &
      ! Delay plant response in Ags
      lrelaxgc_surf, kgc_surf, lrelaxci_surf, kci_surf, &
      ! Soil properties
      phi, phifc, phiwp, R10, &
      !2leaf AGS, sunlit/shaded
      lsplitleaf,l3leaves,sigma


    ! 1    -   Initialize soil

    !if (isurf == 1) then

    ! 1.0  -   Read LSM-specific namelist

    if(myid==0)then
      open(ifnamopt,file=fname_options,status='old',iostat=ierr)
      read (ifnamopt,NAMSURFACE,iostat=ierr)
      if (ierr > 0) then
        print *, 'Problem in namoptions NAMSURFACE'
        print *, 'iostat error: ', ierr
        stop 'ERROR: Problem in namoptions NAMSURFACE'
      endif
      write(6 ,NAMSURFACE)
      close(ifnamopt)
    end if

    call MPI_BCAST(isurf        , 1       , MPI_INTEGER, 0, comm3d, mpierr)
    call MPI_BCAST(tsoilav      , ksoilmax, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(tsoildeepav  , 1       , MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(phiwav       , ksoilmax, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(rootfav      , ksoilmax, MY_REAL, 0, comm3d, mpierr)

    call MPI_BCAST(lmostlocal   , 1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(lsmoothflux  , 1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(lneutral     , 1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(z0mav        , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(z0hav        , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(rsisurf2     , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(Cskinav      , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(lambdaskinav , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(albedoav_surf, 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(Qnetav       , 1, MY_REAL, 0, comm3d, mpierr)

    call MPI_BCAST(rsminav      , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(rssoilminav  , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(cvegav       , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(Wlav         , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(LAI_surfav        , 1, MY_REAL, 0, comm3d, mpierr)
    call MPI_BCAST(gDav         , 1, MY_REAL, 0, comm3d, mpierr)

    call MPI_BCAST(z0         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ustin      ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wtsurf     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wqsurf     ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(wsvsurf(1:nsv),nsv,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(ps         ,1,MY_REAL   ,0,comm3d,mpierr)
    call MPI_BCAST(thls       ,1,MY_REAL   ,0,comm3d,mpierr)

    call MPI_BCAST(lhetero                    ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(loldtable                  ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(lrsAgs                     ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(lCO2Ags                    ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(xpatches                   ,            1, MPI_INTEGER, 0, comm3d, mpierr)
    call MPI_BCAST(ypatches                   ,            1, MPI_INTEGER, 0, comm3d, mpierr)
    call MPI_BCAST(planttype                  ,            1, MPI_INTEGER, 0, comm3d, mpierr)
    call MPI_BCAST(lrelaxgc_surf              ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(lrelaxci_surf              ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(kgc_surf                   ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(kci_surf                   ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(phi                        ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(phifc                      ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(phiwp                      ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(R10                        ,            1, MY_REAL    , 0, comm3d, mpierr)
    call MPI_BCAST(lsplitleaf                 ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(l3leaves                   ,            1, MPI_LOGICAL, 0, comm3d, mpierr)
    call MPI_BCAST(sigma                      ,            1, MY_REAL    , 0, comm3d, mpierr)
    
    call MPI_BCAST(land_use(1:mpatch,1:mpatch),mpatch*mpatch, MPI_INTEGER, 0, comm3d, mpierr)

    if(lCO2Ags .and. (.not. lrsAgs)) then
      if(myid==0) print *,"WARNING::: You set lCO2Ags to .true., but lrsAgs to .false."
      if(myid==0) print *,"WARNING::: Since AGS does not run, lCO2Ags will be set to .false. as well."
      lCO2Ags = .false.
    endif
    if(lsplitleaf .and. (.not. (rad_shortw .and. ((iradiation.eq.irad_par).or.(iradiation .eq. irad_user) .or. (iradiation .eq. irad_rrtmg))))) then
      if(myid==0) stop "WARNING::: You set lsplitleaf to .true., but that needs direct and diffuse calculations. Make sure you enable rad_shortw"
      if(myid==0) stop "WARNING::: Since there is no direct and diffuse radiation calculated in the atmopshere, we set lsplitleaf to .false."
      lsplitleaf = .false.
    endif

    if(lrsAgs) then
      if(planttype==4) then !C4 plants, so standard settings for C3 plants are replaced
        CO2comp298 =    4.3 !<  CO2 compensation concentration
        Q10CO2     =    1.5 !<  Parameter to calculate the CO2 compensation concentration
        gm298      =   17.5 !<  Mesophyll conductance at 298 K
        Q10gm      =    2.0 !<  Parameter to calculate the mesophyll conductance
        T1gm       =  286.0 !<  Reference temperature to calculate the mesophyll conductance
        T2gm       =  309.0 !<  Reference temperature to calculate the mesophyll conductance
        f0         =   0.85 !<  Maximum value Cfrac
        ad         =   0.15 !<  Regression coefficient to calculate Cfrac
        Ammax298   =    1.7 !<  CO2 maximal primary productivity
        Q10am      =    2.0 !<  Parameter to calculate maximal primary productivity
        T1Am       =    286 !<  Reference temperature to calculate maximal primary productivity
        T2Am       =    311 !<  Reference temperature to calculate maximal primary productivity
        alpha0     =  0.014 !<  Initial low light conditions
      else
        if(planttype/=3) then
          if(myid==0) print *,"WARNING::: planttype should be either 3 or 4, corresponding to C3 or C4 plants. It now defaulted to 3."
        endif
      endif
    endif

    if(lhetero) then

      if(xpatches .gt. mpatch) then
        stop "NAMSURFACE: more xpatches defined than possible (change mpatch in modsurfdata to a higher value)"
      endif
      if(ypatches .gt. mpatch) then
        stop "NAMSURFACE: more ypatches defined than possible (change mpatch in modsurfdata to a higher value)"
      endif
      if (lsmoothflux .eqv. .true.) write(6,*) 'WARNING: You selected to use uniform heat fluxes (lsmoothflux) and ',&
      'heterogeneous surface conditions (lhetero) at the same time'
      if (mod(itot,xpatches) .ne. 0) stop "NAMSURFACE: Not an integer amount of grid points per patch in the x-direction"
      if (mod(jtot,ypatches) .ne. 0) stop "NAMSURFACE: Not an integer amount of grid points per patch in the y-direction"

      allocate(z0mav_patch(xpatches,ypatches))
      allocate(z0hav_patch(xpatches,ypatches))
      allocate(thls_patch(xpatches,ypatches))
      allocate(qts_patch(xpatches,ypatches))
      allocate(thvs_patch(xpatches,ypatches))
      allocate(ps_patch(xpatches,ypatches))
      allocate(ustin_patch(xpatches,ypatches))
      allocate(wt_patch(xpatches,ypatches))
      allocate(wq_patch(xpatches,ypatches))
      allocate(wsv_patch(100,xpatches,ypatches))
      allocate(rsisurf2_patch(xpatches,ypatches))
      allocate(albedo_patch(xpatches,ypatches))

      allocate(tsoil_patch(ksoilmax,xpatches,ypatches))
      allocate(tsoildeep_patch(xpatches,ypatches))
      allocate(phiw_patch(ksoilmax,xpatches,ypatches))
      allocate(rootf_patch(ksoilmax,xpatches,ypatches))
      allocate(Cskin_patch(xpatches,ypatches))
      allocate(lambdaskin_patch(xpatches,ypatches))
      allocate(Qnet_patch(xpatches,ypatches))
      allocate(cveg_patch(xpatches,ypatches))
      allocate(Wl_patch(xpatches,ypatches))
      allocate(rsmin_patch(xpatches,ypatches))
      allocate(LAI_patch(xpatches,ypatches))
      allocate(gD_patch(xpatches,ypatches))

      allocate(oblpatch(xpatches,ypatches))

      z0mav_patch = -1
      z0hav_patch = -1
      thls_patch  = -1
      qts_patch   = -1
      thvs_patch  = -1
      ps_patch    = -1
      ustin_patch = -1
      wt_patch    = -1
      wq_patch    = -1
      wsv_patch   = -1
      rsisurf2_patch = 0
      albedo_patch= -1

      tsoil_patch      = -1
      tsoildeep_patch  = -1
      phiw_patch       = -1
      rootf_patch      = -1
      Cskin_patch      = -1
      lambdaskin_patch = -1
      Qnet_patch       = -1
      cveg_patch       = -1
      Wl_patch         = -1
      rsmin_patch      = -1
      LAI_patch        = -1
      gD_patch         = -1

      oblpatch         = -0.1

      defined_landtypes = 0
      if(loldtable) then !Old input-file for heterogeneous surfaces: only valid w/o sw-radiation (due to albedo) and isurf = 3,4
        open (ifinput,file='surface.inp.'//cexpnr)
        ierr = 0
        do while (ierr == 0)
          read(ifinput, '(A)', iostat=ierr) readbuffer
          if (ierr == 0) then                               !So no end of file is encountered
            if (readbuffer(1:1)=='#') then
              if (myid == 0)   print *,trim(readbuffer)
            else
              if (myid == 0)   print *,trim(readbuffer)
              defined_landtypes = defined_landtypes + 1
              i = defined_landtypes
              read(readbuffer, *, iostat=ierr) landtype(i), landname(i), z0mav_land(i), z0hav_land(i), thls_land(i), &
                ps_land(i), ustin_land(i), wt_land(i), wq_land(i), wsv_land(1:nsv,i)

              if (ustin_land(i) .lt. 0) then
                if (myid == 0) stop "NAMSURFACE: A ustin value in the surface input file is negative"
              endif
              if(isurf .ne. 3) then
                if(z0mav_land(i) .lt. 0) then
                  if (myid == 0) stop "NAMSURFACE: a z0mav value is not set or negative in the surface input file"
                end if
                if(z0hav_land(i) .lt. 0) then
                  if (myid == 0) stop "NAMSURFACE: a z0hav value is not set or negative in the surface input file"
                end if
              end if

              if (landtype(i) .eq. 0) landtype_0 = i
              do j = 1, (i-1)
                if (landtype(i) .eq. landtype(j)) stop "NAMSURFACE: Two land types have the same type number"
              enddo

            endif
          endif
        enddo
        close(ifinput)
      else
        select case (isurf)
          case (1) ! Interactive land surface
            open (ifinput,file='surface.interactive.inp.'//cexpnr)
            ierr = 0
            do while (ierr == 0)
              read(ifinput, '(A)', iostat=ierr) readbuffer
              if (ierr == 0) then                               !So no end of file is encountered
                if (readbuffer(1:1)=='#') then
                  if (myid == 0)   print *,trim(readbuffer)
                else
                  if (myid == 0)   print *,trim(readbuffer)
                  defined_landtypes = defined_landtypes + 1
                  i = defined_landtypes
                  read(readbuffer, *, iostat=ierr) landtype(i), landname(i), z0mav_land(i), z0hav_land(i), ps_land(i), &
                    albedo_land(i),tsoil_land(1:ksoilmax,i),tsoildeep_land(i),phiw_land(1:ksoilmax,i),rootf_land(1:ksoilmax,i),&
                    Cskin_land(i), lambdaskin_land(i), Qnet_land(i), cveg_land(i), Wl_land(i), rsmin_land(i), LAI_land(i), &
                    gD_land(i), wsv_land(1:nsv,i)

                  if(z0mav_land(i) .lt. 0) then
                    if (myid == 0) stop "NAMSURFACE: a z0mav value is not set or negative in the surface input file"
                  end if
                  if(z0hav_land(i) .lt. 0) then
                    if (myid == 0) stop "NAMSURFACE: a z0hav value is not set or negative in the surface input file"
                  end if
                  if (albedo_land(i) .lt. 0) then
                    if (myid == 0) stop "NAMSURFACE: An albedo value in the surface input file is negative"
                  endif
                  if (albedo_land(i) .gt. 1) then
                    if (myid == 0) stop "NAMSURFACE: An albedo value in the surface input file is greater than 1"
                  endif

                  if (landtype(i) .eq. 0) landtype_0 = i
                  do j = 1, (i-1)
                    if (landtype(i) .eq. landtype(j)) stop "NAMSURFACE: Two land types have the same type number"
                  enddo

                endif
              endif
            enddo
            close(ifinput)

          case default ! Prescribed land surfaces: isurf = 2, 3, 4 (& 10)
            open (ifinput,file='surface.prescribed.inp.'//cexpnr)
            ierr = 0
            do while (ierr == 0)
              read(ifinput, '(A)', iostat=ierr) readbuffer
              if (ierr == -1) then
                if (myid == 0)  print *, "iostat = ",ierr,": No file ",'surface.prescribed.inp.'//cexpnr," found"
              endif
              if (ierr == 0) then                               !So no end of file is encountered
                if (readbuffer(1:1)=='#') then
                  if (myid == 0)   print *,trim(readbuffer)
                else
                  if (myid == 0)   print *,trim(readbuffer)
                  defined_landtypes = defined_landtypes + 1
                  i = defined_landtypes
                  read(readbuffer, *, iostat=ierr) landtype(i), landname(i), z0mav_land(i), z0hav_land(i), thls_land(i), &
                    ps_land(i), albedo_land(i), rsisurf2_land(i), ustin_land(i), wt_land(i), wq_land(i), wsv_land(1:nsv,i)

                  if (ustin_land(i) .lt. 0) then
                    if (myid == 0) stop "NAMSURFACE: A ustin value in the surface input file is negative"
                  endif
                  if (albedo_land(i) .lt. 0) then
                    if (myid == 0) stop "NAMSURFACE: An albedo value in the surface input file is negative"
                  endif
                  if (albedo_land(i) .gt. 1) then
                    if (myid == 0) stop "NAMSURFACE: An albedo value in the surface input file is greater than 1"
                  endif
                  if(isurf .ne. 3) then
                    if(z0mav_land(i) .lt. 0) then
                      if (myid == 0) stop "NAMSURFACE: a z0mav value is not set or negative in the surface input file"
                    end if
                    if(z0hav_land(i) .lt. 0) then
                      if (myid == 0) stop "NAMSURFACE: a z0hav value is not set or negative in the surface input file"
                    end if
                  end if

                  if (landtype(i) .eq. 0) landtype_0 = i
                  do j = 1, (i-1)
                    if (landtype(i) .eq. landtype(j)) stop "NAMSURFACE: Two land types have the same type number"
                  enddo

                endif
              endif
            enddo
            close(ifinput)
        end select
      endif

      if (myid == 0) then
        if (landtype_0 .eq. -1) then
          stop "NAMSURFACE: no standard land type (0) is defined"
        else
          print "(a,i2,a,i2)","There are ",defined_landtypes,&
          " land types defined in the surface input file. The standard land type is defined by line ",landtype_0
        endif
      endif

      select case (isurf)
        case (1) ! Interactive land surface
          tsoilav      = 0
          tsoildeepav  = 0
          phiwav       = 0
          rootfav      = 0
          Cskinav      = 0
          lambdaskinav = 0
          albedoav_surf     = 0
          Qnetav       = 0
          cvegav       = 0
          rsminav      = 0
          LAI_surfav        = 0
          gDav         = 0
          Wlav         = 0

          z0mav        = 0
          z0hav        = 0
          ps           = 0
          thls         = 300

          do i = 1, xpatches
            do j = 1, ypatches
              landindex = landtype_0
              do k = 1, defined_landtypes
                if (landtype(k) .eq. land_use(i,j)) then
                  landindex = k
                endif
              enddo

              tsoil_patch(:,i,j)    = tsoil_land(:,landindex)
              tsoildeep_patch(i,j)  = tsoildeep_land(landindex)
              phiw_patch(:,i,j)     = phiw_land(:,landindex)
              rootf_patch(:,i,j)    = rootf_land(:,landindex)
              Cskin_patch(i,j)      = Cskin_land(landindex)
              lambdaskin_patch(i,j) = lambdaskin_land(landindex)
              albedo_patch(i,j)     = albedo_land(landindex)
              Qnet_patch(i,j)       = Qnet_land(landindex)
              cveg_patch(i,j)       = cveg_land(landindex)
              rsmin_patch(i,j)      = rsmin_land(landindex)
              LAI_patch(i,j)        = LAI_land(landindex)
              gD_patch(i,j)         = gD_land(landindex)
              Wl_patch(i,j)         = Wl_land(landindex)

              z0mav_patch(i,j)     = z0mav_land(landindex)
              z0hav_patch(i,j)     = z0hav_land(landindex)
              ps_patch(i,j)        = ps_land(landindex)

              wsv_patch(1:nsv,i,j) = wsv_land(1:nsv,landindex)

              tsoilav(:)    = tsoilav(:)   +  ( tsoil_patch(:,i,j)    / ( xpatches * ypatches ) )
              tsoildeepav   = tsoildeepav  +  ( tsoildeep_patch(i,j)  / ( xpatches * ypatches ) )
              phiwav(:)     = phiwav(:)    +  ( phiw_patch(:,i,j)     / ( xpatches * ypatches ) )
              rootfav(:)    = rootfav(:)   +  ( rootf_patch(:,i,j)    / ( xpatches * ypatches ) )
              Cskinav       = Cskinav      +  ( Cskin_patch(i,j)      / ( xpatches * ypatches ) )
              lambdaskinav  = lambdaskinav +  ( lambdaskin_patch(i,j) / ( xpatches * ypatches ) )
              albedoav_surf      = albedoav_surf     +  ( albedo_patch(i,j)     / ( xpatches * ypatches ) )
              Qnetav        = Qnetav       +  ( Qnet_patch(i,j)       / ( xpatches * ypatches ) )
              cvegav        = cvegav       +  ( cveg_patch(i,j)       / ( xpatches * ypatches ) )
              rsminav       = rsminav      +  ( rsmin_patch(i,j)      / ( xpatches * ypatches ) )
              LAI_surfav         = LAI_surfav        +  ( LAI_patch(i,j)        / ( xpatches * ypatches ) )
              gDav          = gDav         +  ( gD_patch(i,j)         / ( xpatches * ypatches ) )
              Wlav          = Wlav         +  ( Wl_patch(i,j)         / ( xpatches * ypatches ) )

              z0mav         = z0mav        +  ( z0mav_patch(i,j)      / ( xpatches * ypatches ) )
              z0hav         = z0hav        +  ( z0hav_patch(i,j)      / ( xpatches * ypatches ) )
              ps            = ps           +  ( ps_patch(i,j)         / ( xpatches * ypatches ) )
            enddo
          enddo
        case default ! Prescribed land surfaces: isurf = 2, 3, 4 (& 10)
          thls   = 0
          ps     = 0
          ustin  = 0
          wtsurf = 0
          wqsurf = 0
          wsvsurf(1:nsv) = 0
          if (.not. loldtable) then
            albedoav_surf  = 0
          endif

          z0mav        = 0
          z0hav        = 0

          do i = 1, xpatches
            do j = 1, ypatches
              landindex = landtype_0
              do k = 1, defined_landtypes
                if (landtype(k) .eq. land_use(i,j)) then
                  landindex = k
                endif
              enddo

              z0mav_patch(i,j)     = z0mav_land(landindex)
              z0hav_patch(i,j)     = z0hav_land(landindex)
              thls_patch(i,j)      = thls_land(landindex)
              ps_patch(i,j)        = ps_land(landindex)
              ustin_patch(i,j)     = ustin_land(landindex)
              wt_patch(i,j)        = wt_land(landindex)
              wq_patch(i,j)        = wq_land(landindex)
              wsv_patch(1:nsv,i,j) = wsv_land(1:nsv,landindex)
              if (.not. loldtable) then
                albedo_patch(i,j)  = albedo_land(landindex)
                rsisurf2_patch(i,j)= rsisurf2_land(landindex)
              endif

              thls   = thls   + ( thls_patch(i,j)  / ( xpatches * ypatches ) )
              ps     = ps     + ( ps_patch(i,j)    / ( xpatches * ypatches ) )
              ustin  = ustin  + ( ustin_patch(i,j) / ( xpatches * ypatches ) )
              wtsurf = wtsurf + ( wt_patch(i,j)    / ( xpatches * ypatches ) )
              wqsurf = wqsurf + ( wq_patch(i,j)    / ( xpatches * ypatches ) )
              wsvsurf(1:nsv) = wsvsurf(1:nsv) + ( wsv_patch(1:nsv,i,j) / ( xpatches * ypatches ) )
              if (.not. loldtable) then
                albedoav_surf  = albedoav_surf + ( albedo_patch(i,j) / ( xpatches * ypatches ) )
              endif

              z0mav  = z0mav  + ( z0mav_patch(i,j) / ( xpatches * ypatches ) )
              z0hav  = z0hav  + ( z0hav_patch(i,j) / ( xpatches * ypatches ) )
            enddo
          enddo
      end select
    else
      if((z0mav == -1 .and. z0hav == -1) .and. (z0 .ne. -1)) then
        z0mav = z0
        z0hav = z0
        write(6,*) "WARNING: z0m and z0h not defined, set equal to z0"
      end if

      if(isurf .ne. 3) then
        if(z0mav == -1) then
          stop "NAMSURFACE: z0mav is not set"
        end if
        if(z0hav == -1) then
          stop "NAMSURFACE: z0hav is not set"
        end if
      end if

    endif


    if(isurf == 1) then
      if(tsoilav(1) == -1 .or. tsoilav(2) == -1 .or. tsoilav(3) == -1 .or. tsoilav(4) == -1) then
        stop "NAMSURFACE: tsoil is not set"
      end if
      if(tsoildeepav == -1) then
        stop "NAMSURFACE: tsoildeep is not set"
      end if
      if(phiwav(1) == -1 .or. phiwav(2) == -1 .or. phiwav(3) == -1 .or. phiwav(4) == -1) then
        stop "NAMSURFACE: phiw is not set"
      end if
      if(rootfav(1) == -1 .or. rootfav(2) == -1 .or. rootfav(3) == -1 .or. rootfav(4) == -1) then
        stop "NAMSURFACE: rootf is not set"
      end if
      if(Cskinav == -1) then
        stop "NAMSURFACE: Cskinav is not set"
      end if
      if(lambdaskinav == -1) then
        stop "NAMSURFACE: lambdaskinav is not set"
      end if
      if(albedoav_surf == -1) then
        stop "NAMSURFACE: albedoav_surf is not set"
      end if
      if(Qnetav == -1) then
        stop "NAMSURFACE: Qnetav is not set"
      end if
      if(cvegav == -1) then
        stop "NAMSURFACE: cvegav is not set"
      end if
      if(rsminav == -1) then
        stop "NAMSURFACE: rsminav is not set"
      end if
      if(rssoilminav == -1) then
        print *,"WARNING: RSSOILMINAV is undefined... RSMINAV will be used as a proxy"
        rssoilminav = rsminav
      end if
      if(LAI_surfav == -1) then
        stop "NAMSURFACE: LAI_surfav is not set"
      end if
      if(gDav == -1) then
        stop "NAMSURFACE: gDav is not set"
      end if
      if(Wlav == -1) then
        stop "NAMSURFACE: Wlav is not set"
      end if
    end if

    if (isurf==1) then
      call initlsm
    end if

    allocate(rs(i2,j2))
    if(isurf <= 2) then
      allocate(ra(i2,j2))

      ! CvH set initial values for rs and ra to be able to compute qskin_surf
      ra = 50.
      if(isurf == 1) then
        rs = 100.
      else
        rs = rsisurf2
      end if
    end if

    allocate(albedo_surf(i2,j2))
    allocate(z0m(i2,j2))
    allocate(z0h(i2,j2))
    allocate(obl(i2,j2))
    allocate(tskin_surf(i2,j2))
    allocate(qskin_surf(i2,j2))
    allocate(Cm(i2,j2))
    allocate(Cs(i2,j2))

    if(rad_shortw .and. albedoav_surf == -1) then
      stop "NAMSURFACE: albedoav_surf is not set"
    end if
    if(iradiation == 1) then
      if(albedoav_surf == -1) then
        stop "NAMSURFACE: albedoav_surf is not set"
      end if
      allocate(swdavn(i2,j2,nradtime))
      allocate(swuavn(i2,j2,nradtime))
      allocate(lwdavn(i2,j2,nradtime))
      allocate(lwuavn(i2,j2,nradtime))
      swdavn =  0.
      swuavn =  0.
      lwdavn =  0.
      lwuavn =  0.
    end if

    albedo_surf     = albedoav_surf
    if(lhetero) then
      do j=1,j2
        tempy=patchynr(j)
        do i=1,i2
          tempx=patchxnr(i)
          z0m(i,j)   = z0mav_patch(tempx,tempy)
          z0h(i,j)   = z0hav_patch(tempx,tempy)
          if (.not. loldtable) then
            albedo_surf(i,j) = albedo_patch(tempx,tempy)
            if(isurf .ne. 1) then
              rs(i,j)     = rsisurf2_patch(tempx,tempy)
            endif
          endif
        enddo
      enddo
    else
      z0m        = z0mav
      z0h        = z0hav
    endif
    
    !XPB Use surface albedo for radiation, unless lcanopyeb=true. 
    !    If so, albedo_rad is overwritten by albedo_can
    albedo_rad(:,:) = albedo_surf(:,:)
    ! 3. Initialize surface layer
    allocate(ustar   (i2,j2))

    allocate(dudz    (i2,j2))
    allocate(dvdz    (i2,j2))

    allocate(thlflux (i2,j2))
    allocate(qtflux  (i2,j2))
    allocate(dqtdz   (i2,j2))
    allocate(dthldz  (i2,j2))
    allocate(svflux  (i2,j2,nsv))
    allocate(svs(nsv))

    if (lrsAgs) then
      allocate(AnField   (2:i1,2:j1))
      allocate(gcco2Field(2:i1,2:j1))
      allocate(RespField (2:i1,2:j1))
      allocate(wco2Field (2:i1,2:j1))
      allocate(rsco2Field(2:i1,2:j1))
      allocate(fstrField (2:i1,2:j1))
      allocate(gc_old    (2:i1,2:j1))
      allocate(ci_old    (2:i1,2:j1))
      allocate(tauField  (2:i1,2:j1))
      allocate(ciField   (2:i1,2:j1))
      allocate(PARField  (2:i1,2:j1))
      if (lsplitleaf) then
        allocate(PARdirField   (2:i1,2:j1))
        allocate(PARdifField   (2:i1,2:j1))
        allocate(PARleaf_shad(nz_gauss))
        allocate(PARleaf_allsun(nz_gauss))
        allocate(PARleaf_sun(nz_gauss,nangle_gauss))
        allocate(fSL(nz_gauss))
        allocate(gshad_old(2:i1,2:j1,nz_gauss))
        allocate(albdir_lsplit(2:i1,2:j1))
        allocate(albdif_lsplit(2:i1,2:j1))
        allocate(albswd_lsplit(2:i1,2:j1))
        allocate(swdir_lsplit(2:i1,2:j1,nz_gauss))
        allocate(swdif_lsplit(2:i1,2:j1,nz_gauss))
        allocate(swu_lsplit(2:i1,2:j1,nz_gauss))
        allocate(PARdir_lsplit(nz_gauss))
        allocate(PARdif_lsplit(nz_gauss))
        allocate(PARu_lsplit  (nz_gauss))
        if (l3leaves) then
          allocate(gleafsun_old(2:i1,2:j1,nz_gauss,nangle_gauss))
        else
          allocate(gsun_old(2:i1,2:j1,nz_gauss))
        endif
      endif  
    endif
    return
  end subroutine initsurface

!> Calculates the interaction with the soil, the surface temperature and humidity, and finally the surface fluxes.
  subroutine surface
    use modglobal,  only : i1,i2,j1,j2,fkar,zf,cu,cv,nsv,ijtot,rd,rv
    use modfields,  only : thl0, qt0, u0, v0, u0av, v0av
    use modmpi,     only : my_real, mpierr, comm3d, mpi_sum, excj, excjs, mpi_integer,myid
    use moduser,    only : surf_user
    use modraddata, only : tskin_rad,albedo_rad,qskin_rad
    use modcanopy,  only : lcanopyeb
    implicit none

    integer  :: i, j, n, patchx, patchy
    real     :: upcu, vpcv, horv, horvav, horvpatch(xpatches,ypatches)
    real     :: upatch(xpatches,ypatches), vpatch(xpatches,ypatches)
    real     :: Supatch(xpatches,ypatches), Svpatch(xpatches,ypatches)
    integer  :: Npatch(xpatches,ypatches), SNpatch(xpatches,ypatches)
    real     :: lthls_patch(xpatches,ypatches)
    real     :: lqts_patch(xpatches,ypatches)!, qts_patch(xpatches,ypatches)
    real     :: phimzf, phihzf
    real     :: thlsl, qtsl

    real     :: ust,ustl
    real     :: wtsurfl, wqsurfl

    patchx = 0
    patchy = 0

    if (isurf==10) then
      call surf_user
      return
    end if

    if(lhetero) then
      upatch = 0
      vpatch = 0
      Npatch = 0

      do j = 2, j1
        do i = 2, i1
          patchx = patchxnr(i)
          patchy = patchynr(j)
          upatch(patchx,patchy) = upatch(patchx,patchy) + 0.5 * (u0(i,j,1) + u0(i+1,j,1))
          vpatch(patchx,patchy) = vpatch(patchx,patchy) + 0.5 * (v0(i,j,1) + v0(i,j+1,1))
          Npatch(patchx,patchy) = Npatch(patchx,patchy) + 1
        enddo
      enddo

      call MPI_ALLREDUCE(upatch(1:xpatches,1:ypatches),Supatch(1:xpatches,1:ypatches),&
      xpatches*ypatches,    MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(vpatch(1:xpatches,1:ypatches),Svpatch(1:xpatches,1:ypatches),&
      xpatches*ypatches,    MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(Npatch(1:xpatches,1:ypatches),SNpatch(1:xpatches,1:ypatches),&
      xpatches*ypatches,MPI_INTEGER,MPI_SUM, comm3d,mpierr)

      horvpatch = sqrt(((Supatch/SNpatch) + cu) **2. + ((Svpatch/SNpatch) + cv) ** 2.)
      horvpatch = max(horvpatch, 0.1)
    endif


    ! CvH start with computation of drag coefficients to allow for implicit solver
    if(isurf <= 2) then

      if(lneutral) then
        obl(:,:) = -1.e10
        oblav    = -1.e10
      else
        call getobl
      end if

      call MPI_BCAST(oblav ,1,MY_REAL ,0,comm3d,mpierr)

      do j = 2, j1
        do i = 2, i1
          if(lhetero) then
            patchx = patchxnr(i)
            patchy = patchynr(j)
          endif

          ! 3     -   Calculate the drag coefficient and aerodynamic resistance
          Cm(i,j) = fkar ** 2. / (log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j)) + psim(z0m(i,j) / obl(i,j))) ** 2.
          Cs(i,j) = fkar ** 2. / (log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j)) + psim(z0m(i,j) / obl(i,j))) / &
          (log(zf(1) / z0h(i,j)) - psih(zf(1) / obl(i,j)) + psih(z0h(i,j) / obl(i,j)))

          if(lmostlocal) then
            upcu  = 0.5 * (u0(i,j,1) + u0(i+1,j,1)) + cu
            vpcv  = 0.5 * (v0(i,j,1) + v0(i,j+1,1)) + cv
            horv  = sqrt(upcu ** 2. + vpcv ** 2.)
            horv  = max(horv, 0.1)
            ra(i,j) = 1. / ( Cs(i,j) * horv )
          else
            if (lhetero) then
              ra(i,j) = 1. / ( Cs(i,j) * horvpatch(patchx,patchy) )
            else
              horvav  = sqrt(u0av(1) ** 2. + v0av(1) ** 2.)
              horvav  = max(horvav, 0.1)
              ra(i,j) = 1. / ( Cs(i,j) * horvav )
            endif
          end if

        end do
      end do
    end if

    ! Solve the surface energy balance and the heat and moisture transport in the soil
    if(isurf == 1) then
      call do_lsm

    elseif(isurf == 2) then
      do j = 2, j1
        do i = 2, i1
          if(lhetero) then
            tskin_surf(i,j) = thls_patch(patchxnr(i),patchynr(j))
          else
            tskin_surf(i,j) = thls
          endif
        end do
      end do

      call qtsurf

    end if

    ! 2     -   Calculate the surface fluxes
    if(isurf <= 2) then
      do j = 2, j1
        do i = 2, i1
          upcu   = 0.5 * (u0(i,j,1) + u0(i+1,j,1)) + cu
          vpcv   = 0.5 * (v0(i,j,1) + v0(i,j+1,1)) + cv
          horv   = sqrt(upcu ** 2. + vpcv ** 2.)
          horv   = max(horv, 0.1)
          horvav = sqrt(u0av(1) ** 2. + v0av(1) ** 2.)
          horvav = max(horvav, 0.1)

          if(lhetero) then
            patchx = patchxnr(i)
            patchy = patchynr(j)
          endif

          if(lmostlocal) then
            ustar  (i,j) = sqrt(Cm(i,j)) * horv
          else
            if(lhetero) then
              ustar  (i,j) = sqrt(Cm(i,j)) * horvpatch(patchx,patchy)
            else
              ustar  (i,j) = sqrt(Cm(i,j)) * horvav
            endif
          end if

          thlflux(i,j) = - ( thl0(i,j,1) - tskin_surf(i,j) ) / ra(i,j)
          qtflux(i,j) = - (qt0(i,j,1)  - qskin_surf(i,j)) / ra(i,j)

          if(lhetero) then
            do n=1,nsv
              svflux(i,j,n) = wsv_patch(n,patchx,patchy)
            enddo
          else
            do n=1,nsv
              svflux(i,j,n) = wsvsurf(n)
            enddo
          endif

          if(lCO2Ags) svflux(i,j,indCO2) = CO2flux(i,j)

          phimzf = phim(zf(1)/obl(i,j))
          phihzf = phih(zf(1)/obl(i,j))
          
          dudz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(upcu/horv)
          dvdz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(vpcv/horv)
          dthldz(i,j) = - thlflux(i,j) / ustar(i,j) * phihzf / (fkar*zf(1))
          dqtdz (i,j) = - qtflux(i,j)  / ustar(i,j) * phihzf / (fkar*zf(1))
        end do
      end do

      if(lsmoothflux) then

        ustl    = sum(ustar  (2:i1,2:j1))
        wtsurfl = sum(thlflux(2:i1,2:j1))
        wqsurfl = sum(qtflux (2:i1,2:j1))

        call MPI_ALLREDUCE(ustl, ust, 1,  MY_REAL,MPI_SUM, comm3d,mpierr)
        call MPI_ALLREDUCE(wtsurfl, wtsurf, 1,  MY_REAL,MPI_SUM, comm3d,mpierr)
        call MPI_ALLREDUCE(wqsurfl, wqsurf, 1,  MY_REAL,MPI_SUM, comm3d,mpierr)

        wtsurf = wtsurf / ijtot
        wqsurf = wqsurf / ijtot

        do j = 2, j1
          do i = 2, i1

            thlflux(i,j) = wtsurf
            qtflux (i,j) = wqsurf

            do n=1,nsv
              svflux(i,j,n) = wsvsurf(n)
            enddo

            phimzf = phim(zf(1)/obl(i,j))
            phihzf = phih(zf(1)/obl(i,j))
            
            upcu  = 0.5 * (u0(i,j,1) + u0(i+1,j,1)) + cu
            vpcv  = 0.5 * (v0(i,j,1) + v0(i,j+1,1)) + cv
            horv  = sqrt(upcu ** 2. + vpcv ** 2.)
            horv  = max(horv, 0.1)

            dudz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(upcu/horv)
            dvdz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(vpcv/horv)
            dthldz(i,j) = - thlflux(i,j) / ustar(i,j) * phihzf / (fkar*zf(1))
            dqtdz (i,j) = - qtflux(i,j)  / ustar(i,j) * phihzf / (fkar*zf(1))
          end do
        end do

      end if

    else

      if(lneutral) then
        obl(:,:) = -1.e10
        oblav    = -1.e10
      else
        call getobl
      end if

      thlsl = 0.
      qtsl  = 0.

      if(lhetero) then
        lthls_patch = 0.0
        lqts_patch  = 0.0
        Npatch      = 0
      endif

      do j = 2, j1
        do i = 2, i1
          if(lhetero) then
            patchx = patchxnr(i)
            patchy = patchynr(j)
          endif

          upcu   = 0.5 * (u0(i,j,1) + u0(i+1,j,1)) + cu
          vpcv   = 0.5 * (v0(i,j,1) + v0(i,j+1,1)) + cv
          horv   = sqrt(upcu ** 2. + vpcv ** 2.)
          horv   = max(horv, 0.1)
          horvav = sqrt(u0av(1) ** 2. + v0av(1) ** 2.)
          horvav = max(horvav, 0.1)
          if( isurf == 4) then
            if(lmostlocal) then
              ustar (i,j) = fkar * horv  / (log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j)) + psim(z0m(i,j) / obl(i,j)))
            else
              if(lhetero) then
                ustar (i,j) = fkar * horvpatch(patchx,patchy) / (log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j))&
                + psim(z0m(i,j) / obl(i,j)))
              else
                ustar (i,j) = fkar * horvav / (log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j)) + psim(z0m(i,j) / obl(i,j)))
              endif
            end if
          else
            if(lhetero) then
              ustar (i,j) = ustin_patch(patchx,patchy)
            else
              ustar (i,j) = ustin
            endif
          end if

          ustar  (i,j) = max(ustar(i,j), 1.e-2)
          if(lhetero) then
            thlflux(i,j) = wt_patch(patchx,patchynr(j))
            qtflux (i,j) = wq_patch(patchx,patchynr(j))
          else
            thlflux(i,j) = wtsurf
            qtflux (i,j) = wqsurf
          endif

          if(lhetero) then
            do n=1,nsv
              svflux(i,j,n) = wsv_patch(n,patchx,patchynr(j))
            enddo
          else
            do n=1,nsv
              svflux(i,j,n) = wsvsurf(n)
            enddo
          endif
         
          phimzf = phim(zf(1)/obl(i,j))
          phihzf = phih(zf(1)/obl(i,j))
          
          dudz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(upcu/horv)
          dvdz  (i,j) = ustar(i,j) * phimzf / (fkar*zf(1))*(vpcv/horv)
          dthldz(i,j) = - thlflux(i,j) / ustar(i,j) * phihzf / (fkar*zf(1))
          dqtdz (i,j) = - qtflux(i,j)  / ustar(i,j) * phihzf / (fkar*zf(1))

          Cs(i,j) = fkar ** 2. / ((log(zf(1) / z0m(i,j)) - psim(zf(1) / obl(i,j)) + psim(z0m(i,j) / obl(i,j))) * &
          (log(zf(1) / z0h(i,j)) - psih(zf(1) / obl(i,j)) + psih(z0h(i,j) / obl(i,j))))

          tskin_surf(i,j) = min(max(thlflux(i,j) / (Cs(i,j) * horv),-10.),10.)  + thl0(i,j,1)
          qskin_surf(i,j) = min(max( qtflux(i,j) / (Cs(i,j) * horv),-5e-2),5e-2) + qt0(i,j,1)

          thlsl      = thlsl + tskin_surf(i,j)
          qtsl       = qtsl  + qskin_surf(i,j)
          if (lhetero) then
            lthls_patch(patchx,patchy) = lthls_patch(patchx,patchy) + tskin_surf(i,j)
            lqts_patch(patchx,patchy)  = lqts_patch(patchx,patchy)  + qskin_surf(i,j)
            Npatch(patchx,patchy)      = Npatch(patchx,patchy)      + 1
          endif
        end do
      end do

      call MPI_ALLREDUCE(thlsl, thls, 1,  MY_REAL, MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(qtsl, qts, 1,  MY_REAL, MPI_SUM, comm3d,mpierr)

      thls = thls / ijtot
      qts  = qts  / ijtot
      thvs = thls * (1. + (rv/rd - 1.) * qts)

      if (lhetero) then
        call MPI_ALLREDUCE(lthls_patch(1:xpatches,1:ypatches), thls_patch(1:xpatches,1:ypatches),&
        xpatches*ypatches,     MY_REAL, MPI_SUM, comm3d,mpierr)
        call MPI_ALLREDUCE(lqts_patch(1:xpatches,1:ypatches),  qts_patch(1:xpatches,1:ypatches),&
        xpatches*ypatches,     MY_REAL, MPI_SUM, comm3d,mpierr)
        call MPI_ALLREDUCE(Npatch(1:xpatches,1:ypatches)     , SNpatch(1:xpatches,1:ypatches),&
        xpatches*ypatches, MPI_INTEGER ,MPI_SUM, comm3d,mpierr)
        thls_patch = thls_patch / SNpatch
        qts_patch  = qts_patch  / SNpatch
        thvs_patch = thls_patch * (1. + (rv/rd - 1.) * qts_patch)
      endif

    !if (lhetero) then
    !  thvs_patch = thls_patch * (1. + (rv/rd - 1.) * qts_patch)
    !endif
      !call qtsurf

    end if

    ! Transfer ustar to neighbouring cells
    call excj( ustar  , 1, i2, 1, j2, 1,1)
    
    !XPB Use surface tskin for radiation, unless lcanopyeb=true. 
    !    If so, tskin_rad is overwritten by tskin_can
    !print *,'tskin_rad modsurf1048',tskin_rad(2,2)
    !print *,'albedo_rad modsurf1048',albedo_rad(2,2)
    !if (lcanopyeb) then
    if (.False.) then !Im not sure tskin from canopy top will help
      if (.not. tskin_set) then ! in first call we use surface ppties because canopy needs rad and is not called yet. Afterwards, canopy top
        tskin_rad (:,:) = tskin_surf (:,:)
        qskin_rad (:,:) = qskin_surf (:,:)
        tskin_set = .true.
      endif
    else ! no canopy, use always surface ppties
        tskin_rad (:,:) = tskin_surf (:,:)
        qskin_rad (:,:) = qskin_surf (:,:)
    endif
    !print *,'tskin_rad modsurf1051',tskin_rad(2,2)
    !print *,'albedo_rad modsurf1051',albedo_rad(2,2)

    return

  end subroutine surface

!> Calculate the surface humidity assuming saturation.
  subroutine qtsurf
    use modglobal,   only : tmelt,bt,at,rd,rv,cp,es0,pref0,ijtot,i1,j1
    use modfields,   only : qt0
    !use modsurfdata, only : rs, ra
    use modmpi,      only : my_real,mpierr,comm3d,mpi_sum,mpi_integer

    implicit none
    real       :: exner, tsurf, qsatsurf, surfwet, es, qtsl
    integer    :: i,j, patchx, patchy
    integer    :: Npatch(xpatches,ypatches), SNpatch(xpatches,ypatches)
    real       :: lqts_patch(xpatches,ypatches)

    patchx = 0
    patchy = 0

    if(isurf <= 2) then
      qtsl = 0.
      do j = 2, j1
        do i = 2, i1
          exner      = (ps / pref0)**(rd/cp)
          tsurf      = tskin_surf(i,j) * exner
          es         = es0 * exp(at*(tsurf-tmelt) / (tsurf-bt))
          qsatsurf   = rd / rv * es / ps
          surfwet    = ra(i,j) / (ra(i,j) + rs(i,j))
          qskin_surf(i,j) = surfwet * qsatsurf + (1. - surfwet) * qt0(i,j,1)
          qtsl       = qtsl + qskin_surf(i,j)
        end do
      end do

      call MPI_ALLREDUCE(qtsl, qts, 1,  MY_REAL, &
                         MPI_SUM, comm3d,mpierr)
      qts  = qts / ijtot
      thvs = thls * (1. + (rv/rd - 1.) * qts)

      if (lhetero) then
        lqts_patch = 0.
        Npatch     = 0
        do j = 2, j1
          do i = 2, i1
            patchx     = patchxnr(i)
            patchy     = patchynr(j)
            exner      = (ps_patch(patchx,patchy) / pref0)**(rd/cp)
            tsurf      = tskin_surf(i,j) * exner
            es         = es0 * exp(at*(tsurf-tmelt) / (tsurf-bt))
            qsatsurf   = rd / rv * es / ps_patch(patchx,patchy)
            surfwet    = ra(i,j) / (ra(i,j) + rs(i,j))
            qskin_surf(i,j) = surfwet * qsatsurf + (1. - surfwet) * qt0(i,j,1)

            lqts_patch(patchx,patchy) = lqts_patch(patchx,patchy) + qskin_surf(i,j)
            Npatch(patchx,patchy)     = Npatch(patchx,patchy)     + 1
          enddo
        enddo
        call MPI_ALLREDUCE(lqts_patch(1:xpatches,1:ypatches), qts_patch(1:xpatches,1:ypatches),&
        xpatches*ypatches,     MY_REAL,MPI_SUM, comm3d,mpierr)
        call MPI_ALLREDUCE(Npatch(1:xpatches,1:ypatches)    , SNpatch(1:xpatches,1:ypatches)  ,&
        xpatches*ypatches,MPI_INTEGER ,MPI_SUM, comm3d,mpierr)
        qts_patch = qts_patch / SNpatch
        thvs_patch = thls_patch * (1. + (rv/rd - 1.) * qts_patch)
      endif
    end if

    return

  end subroutine qtsurf

!> Calculates the Obukhov length iteratively.
  subroutine getobl
    use modglobal, only : zf, rv, rd, grav, i1, j1, i2, j2, cu, cv
    use modfields, only : thl0av, qt0av, u0, v0, thl0, qt0, u0av, v0av
    use modmpi,    only : my_real,mpierr,comm3d,mpi_sum,excj,mpi_integer
    implicit none

    integer             :: i,j,iter,patchx,patchy
    real                :: thv, thvsl, L, horv2, oblavl, thvpatch(xpatches,ypatches), horvpatch(xpatches,ypatches)
    real                :: Rib, Lstart, Lend, fx, fxdif, Lold
    real                :: upcu, vpcv
    real                :: upatch(xpatches,ypatches), vpatch(xpatches,ypatches)
    real                :: Supatch(xpatches,ypatches), Svpatch(xpatches,ypatches)
    integer             :: Npatch(xpatches,ypatches), SNpatch(xpatches,ypatches)
    real                :: lthlpatch(xpatches,ypatches), thlpatch(xpatches,ypatches),&
                           lqpatch(xpatches,ypatches), qpatch(xpatches,ypatches)
    real                :: loblpatch(xpatches,ypatches)

    if(lmostlocal) then

      oblavl = 0.

      do i=2,i1
        do j=2,j1
          thv     =   thl0(i,j,1)  * (1. + (rv/rd - 1.) * qt0(i,j,1))
          thvsl   =   tskin_surf(i,j)   * (1. + (rv/rd - 1.) * qskin_surf(i,j))
          upcu    =   0.5 * (u0(i,j,1) + u0(i+1,j,1)) + cu
          vpcv    =   0.5 * (v0(i,j,1) + v0(i,j+1,1)) + cv
          horv2   =   upcu ** 2. + vpcv ** 2.
          horv2   =   max(horv2, 0.01)

          if(lhetero) then
            patchx = patchxnr(i)
            patchy = patchynr(j)
            Rib    = grav / thvs_patch(patchx,patchy) * zf(1) * (thv - thvsl) / horv2
          else
            Rib    = grav / thvs * zf(1) * (thv - thvsl) / horv2
          endif

          if (Rib == 0) then
             ! Rib can be 0 if there is no surface flux
             ! L is capped at 1e6 below, so use the same cap here
             L = 1e6
             write(*,*) 'Obukhov length: Rib = 0 -> setting L=1e6'
          else
             iter = 0
             L = obl(i,j)

             if(Rib * L < 0. .or. abs(L) == 1e5) then
                if(Rib > 0) L = 0.01
                if(Rib < 0) L = -0.01
             end if
             
             do while (.true.)
                iter    = iter + 1
                Lold    = L
                fx      = Rib - zf(1) / L * (log(zf(1) / z0h(i,j)) - psih(zf(1) / L) + psih(z0h(i,j) / L)) /&
                     (log(zf(1) / z0m(i,j)) - psim(zf(1) / L) + psim(z0m(i,j) / L)) ** 2.
                Lstart  = L - 0.001*L
                Lend    = L + 0.001*L
                fxdif   = ( (- zf(1) / Lstart * (log(zf(1) / z0h(i,j)) - psih(zf(1) / Lstart) + psih(z0h(i,j) / Lstart)) /&
                     (log(zf(1) / z0m(i,j)) - psim(zf(1) / Lstart) + psim(z0m(i,j) / Lstart)) ** 2.) - (-zf(1) / Lend * &
                     (log(zf(1) / z0h(i,j)) - psih(zf(1) / Lend) + psih(z0h(i,j) / Lend)) / (log(zf(1) / z0m(i,j)) - psim(zf(1) / Lend)&
                     + psim(z0m(i,j) / Lend)) ** 2.) ) / (Lstart - Lend)
                L = L - fx / fxdif
                if(Rib * L < 0. .or. abs(L) == 1e5) then
                   if(Rib > 0) L = 0.01
                   if(Rib < 0) L = -0.01
                end if
                if(abs((L - Lold)/L) < 1e-4) exit
                if(iter > 1000) stop 'Obukhov length calculation does not converge!'
             end do

             if (abs(L)>1e6) L = sign(1.0e6,L)
          end if
          obl(i,j) = L

        end do
      end do
    end if

    if(lhetero) then
      upatch    = 0
      vpatch    = 0
      Npatch    = 0
      lthlpatch = 0
      lqpatch   = 0
      loblpatch = 0

      do j = 2, j1
        do i = 2, i1
          patchx = patchxnr(i)
          patchy = patchynr(j)
          upatch(patchx,patchy)    = upatch(patchx,patchy)    + 0.5 * (u0(i,j,1) + u0(i+1,j,1))
          vpatch(patchx,patchy)    = vpatch(patchx,patchy)    + 0.5 * (v0(i,j,1) + v0(i,j+1,1))
          Npatch(patchx,patchy)    = Npatch(patchx,patchy)    + 1
          lthlpatch(patchx,patchy) = lthlpatch(patchx,patchy) + thl0(i,j,1)
          lqpatch(patchx,patchy)   = lqpatch(patchx,patchy)   + qt0(i,j,1)
          loblpatch(patchx,patchy) = loblpatch(patchx,patchy) + obl(i,j)
        enddo
      enddo

      call MPI_ALLREDUCE(upatch(1:xpatches,1:ypatches)   ,Supatch(1:xpatches,1:ypatches) ,xpatches*ypatches,&
      MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(vpatch(1:xpatches,1:ypatches)   ,Svpatch(1:xpatches,1:ypatches) ,xpatches*ypatches,&
      MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(Npatch(1:xpatches,1:ypatches)   ,SNpatch(1:xpatches,1:ypatches) ,xpatches*ypatches,&
      MPI_INTEGER,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(lthlpatch(1:xpatches,1:ypatches),thlpatch(1:xpatches,1:ypatches),xpatches*ypatches,&
      MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(lqpatch(1:xpatches,1:ypatches)  ,qpatch(1:xpatches,1:ypatches)  ,xpatches*ypatches,&
      MY_REAL,MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(loblpatch(1:xpatches,1:ypatches),oblpatch(1:xpatches,1:ypatches),xpatches*ypatches,&
      MY_REAL,MPI_SUM, comm3d,mpierr)

      horvpatch = sqrt(((Supatch/SNpatch) + cu) **2. + ((Svpatch/SNpatch) + cv) ** 2.)
      horvpatch = max(horvpatch, 0.1)

      thlpatch  = thlpatch / SNpatch
      qpatch    = qpatch   / SNpatch
      oblpatch  = oblpatch / SNpatch

      thvpatch  = thlpatch * (1. + (rv/rd - 1.) * qpatch)

      do patchy = 1, ypatches
        do patchx = 1, xpatches
          Rib   = grav / thvs_patch(patchx,patchy) * zf(1) *&
          (thvpatch(patchx,patchy) - thvs_patch(patchx,patchy)) / (horvpatch(patchx,patchy) ** 2.)
          iter = 0
          L = oblpatch(patchx,patchy)

          if(Rib * L < 0. .or. abs(L) == 1e5) then
            if(Rib > 0) L = 0.01
            if(Rib < 0) L = -0.01
          end if

          do while (.true.)
            iter    = iter + 1
            Lold    = L
            fx      = Rib - zf(1) / L * (log(zf(1) / z0hav_patch(patchx,patchy)) - psih(zf(1) / L) +&
            psih(z0hav_patch(patchx,patchy) / L)) / (log(zf(1) / z0mav_patch(patchx,patchy)) - psim(zf(1) / L) &
            + psim(z0mav_patch(patchx,patchy) / L)) ** 2.
            Lstart  = L - 0.001*L
            Lend    = L + 0.001*L
            fxdif   = ( (- zf(1) / Lstart * (log(zf(1) / z0hav_patch(patchx,patchy)) - psih(zf(1) / Lstart) +&
            psih(z0hav_patch(patchx,patchy) / Lstart)) / (log(zf(1) / z0mav_patch(patchx,patchy)) - psim(zf(1) / Lstart) + &
            psim(z0mav_patch(patchx,patchy) / Lstart)) ** 2.) - (-zf(1) / Lend * (log(zf(1) / z0hav_patch(patchx,patchy)) &
            - psih(zf(1) / Lend) + psih(z0hav_patch(patchx,patchy) / Lend)) / &
            (log(zf(1) / z0mav_patch(patchx,patchy)) - psim(zf(1) / Lend) + psim(z0mav_patch(patchx,patchy) / Lend)) ** 2.) )&
            / (Lstart - Lend)
            L       = L - fx / fxdif
            if(Rib * L < 0. .or. abs(L) == 1e5) then
              if(Rib > 0) L = 0.01
              if(Rib < 0) L = -0.01
            end if
            if(abs((L - Lold)/L) < 1e-4) exit
          end do

          if (abs(L)>1e6) L = sign(1.0e6,L)
          oblpatch(patchx,patchy) = L
        enddo
      enddo
      if(.not. lmostlocal) then
        do i=1,i2
          do j=1,j2
            obl(i,j) = oblpatch(patchxnr(i),patchynr(j))
          enddo
        enddo
      endif
    endif

    !CvH also do a global evaluation if lmostlocal = .true. to get an appropriate local mean
    thv    = thl0av(1) * (1. + (rv/rd - 1.) * qt0av(1))

    horv2 = u0av(1)**2. + v0av(1)**2.
    horv2 = max(horv2, 0.01)

    Rib   = grav / thvs * zf(1) * (thv - thvs) / horv2
    if (Rib == 0) then
       ! Rib can be 0 if there is no surface flux
       ! L is capped at 1e6 below, so use the same cap here
       L = 1e6
       write(*,*) 'Obukhov length: Rib = 0 -> setting L=1e6 (2nd point)'
    else
       iter = 0
       L = oblav

       if(Rib * L < 0. .or. abs(L) == 1e5) then
          if(Rib > 0) L = 0.01
          if(Rib < 0) L = -0.01
       end if
       
       do while (.true.)
          iter    = iter + 1
          Lold    = L
          fx      = Rib - zf(1) / L * (log(zf(1) / z0hav) - psih(zf(1) / L) + psih(z0hav / L)) /&
               (log(zf(1) / z0mav) - psim(zf(1) / L) + psim(z0mav / L)) ** 2.
          Lstart  = L - 0.001*L
          Lend    = L + 0.001*L
          fxdif   = ( (- zf(1) / Lstart * (log(zf(1) / z0hav) - psih(zf(1) / Lstart) + psih(z0hav / Lstart)) /&
               (log(zf(1) / z0mav) - psim(zf(1) / Lstart) + psim(z0mav / Lstart)) ** 2.) - (-zf(1) / Lend * (log(zf(1) / z0hav) &
               - psih(zf(1) / Lend) + psih(z0hav / Lend)) / (log(zf(1) / z0mav) - psim(zf(1) / Lend) &
               + psim(z0mav / Lend)) ** 2.) ) / (Lstart - Lend)
          L       = L - fx / fxdif
          if(Rib * L < 0. .or. abs(L) == 1e5) then
             if(Rib > 0) L = 0.01
             if(Rib < 0) L = -0.01
          end if
          if(abs((L - Lold)/L) < 1e-4) exit
          if(iter > 1000) stop 'Obukhov length calculation does not converge!'
       end do

       if (abs(L)>1e6) L = sign(1.0e6,L)
       if(.not. lmostlocal) then
          if(.not. lhetero) then
             obl(:,:) = L
          endif
       end if
    end if
    oblav = L

    return

  end subroutine getobl

  function psim(zeta)
    implicit none

    real             :: psim
    real, intent(in) :: zeta
    real             :: x

    if(zeta <= 0) then
      x     = (1. - 16. * zeta) ** (0.25)
      psim  = 3.14159265 / 2. - 2. * atan(x) + log( (1.+x) ** 2. * (1. + x ** 2.) / 8.)
      ! CvH use Wilson, 2001 rather than Businger-Dyer for correct free convection limit
      !x     = (1. + 3.6 * abs(zeta) ** (2./3.)) ** (-0.5)
      !psim = 3. * log( (1. + 1. / x) / 2.)
    else
      psim  = -2./3. * (zeta - 5./0.35)*exp(-0.35 * zeta) - zeta - (10./3.) / 0.35
    end if

    return
  end function psim

  function psih(zeta)

    implicit none

    real             :: psih
    real, intent(in) :: zeta
    real             :: x

    if(zeta <= 0) then
      x     = (1. - 16. * zeta) ** (0.25)
      psih  = 2. * log( (1. + x ** 2.) / 2. )
      ! CvH use Wilson, 2001
      !x     = (1. + 7.9 * abs(zeta) ** (2./3.)) ** (-0.5)
      !psih  = 3. * log( (1. + 1. / x) / 2.)
    else
      psih  = -2./3. * (zeta - 5./0.35)*exp(-0.35 * zeta) - (1. + (2./3.) * zeta) ** (1.5) - (10./3.) / 0.35 + 1.
    end if

    return
  end function psih

  ! stability function Phi for momentum.
  ! Many functional forms of Phi have been suggested, see e.g. Optis 2015
  ! Phi and Psi above are related by an integral and should in principle match, 
  ! currently they do not.
  ! FJ 2018: For very stable situations, zeta > 1 add cap to phi - the linear expression is valid only for zeta < 1
 function phim(zeta)
    implicit none
    real             :: phim
    real, intent(in) :: zeta

    if (zeta < 0.) then ! unstable
       phim = (1.-16.*zeta)**(-0.25)
       !phimzf = (1. + 3.6 * (-zf(1)/obl(i,j))**(2./3.))**(-0.5)
    elseif ( zeta < 1.) then  ! 0 < zeta < 1, stable
       phim = (1.+5.*zeta)
    else
       phim = 6 ! cap phi when z/L > 1
    endif

    return
  end function phim

   ! stability function Phi for heat.  
 function phih(zeta)
    implicit none
    real             :: phih
    real, intent(in) :: zeta

    if (zeta < 0.) then ! unstable
       phih = (1.-16.*zeta)**(-0.50)
       !phihzf = (1. + 7.9 * (-zf(1)/obl(i,j))**(2./3.))**(-0.5)
    elseif ( zeta < 1.) then  ! 0 < zf(1) / obl < 1, stable
       phih = (1.+5.*zeta)
    else
     phih = 6  ! cap phi when z/L > 1
    endif

    return
  end function phih

  
  function E1(x)
  implicit none
    real             :: E1
    real, intent(in) :: x
    real             :: E1sum!, factorial
    integer          :: k

    E1sum = 0.0
    do k=1,99
      !E1sum = E1sum + (-1.0) ** (k + 0.0) * x ** (k + 0.0) / ( (k + 0.0) * factorial(k) )
       E1sum = E1sum + (-1.0 * x) ** k / ( k * factorial(k) )  ! FJ changed this for compilation with cray fortran
                                                          
    end do
    E1 = -0.57721566490153286060 - log(x) - E1sum

    return
  end function E1

  function factorial(k)
  implicit none
    real                :: factorial
    integer, intent(in) :: k
    integer             :: n
    factorial = 1.0
    do n = 2, k
      factorial = factorial * n
    enddo
  end function factorial

  function patchxnr(xpos)
    use modmpi,     only : myidx
    use modglobal,  only : imax,itot
    implicit none
    integer, intent(in) :: xpos

    integer             :: patchxnr
    integer             :: positionx

    ! Converting the j position to the real j position by taking the processor number into account
    ! First grid point lies at j = 2. Make position = 0 for first grid point

    positionx = xpos + (myidx * imax) - 2

    ! Account for border grid points
    if (positionx .lt. 0)    positionx = positionx + itot
    if (positionx .ge. itot) positionx = positionx - itot

    ! Convert position to patch number
    patchxnr  = 1 + (positionx*xpatches)/itot

    return
  end function

  function patchynr(ypos)
    use modmpi,     only : myidy
    use modglobal,  only : jmax,jtot
    implicit none
    integer, intent(in) :: ypos
    integer             :: patchynr
    integer             :: positiony

    ! Converting the j position to the real j position by taking the processor number into account
    ! First grid point lies at j = 2. Make position = 0 for first gridpoint
    positiony = ypos + (myidy * jmax) - 2

    ! Account for border grid points
    if (positiony .lt. 0)    positiony = positiony + jtot
    if (positiony .ge. jtot) positiony = positiony - jtot

    ! Convert position to patch number
    patchynr  = 1 + (positiony*ypatches)/jtot

    return
  end function

  subroutine exitsurface
    implicit none
    return
  end subroutine exitsurface

  subroutine initlsm
    use modglobal, only : i2,j2
    integer :: k,j,i,tempy,tempx

    ! 1.1  -   Allocate arrays
    allocate(zsoil(ksoilmax))
    allocate(zsoilc(ksoilmax))
    allocate(dzsoil(ksoilmax))
    allocate(dzsoilh(ksoilmax))

    allocate(lambda(i2,j2,ksoilmax))
    allocate(lambdah(i2,j2,ksoilmax))
    allocate(lambdas(i2,j2,ksoilmax))
    allocate(lambdash(i2,j2,ksoilmax))
    allocate(gammas(i2,j2,ksoilmax))
    allocate(gammash(i2,j2,ksoilmax))
    allocate(Dh(i2,j2,ksoilmax))
    allocate(phiw(i2,j2,ksoilmax))
    allocate(phiwm(i2,j2,ksoilmax))
    allocate(phifrac(i2,j2,ksoilmax))
    allocate(pCs(i2,j2,ksoilmax))
    allocate(rootf(i2,j2,ksoilmax))
    allocate(tsoil(i2,j2,ksoilmax))
    allocate(tsoilm(i2,j2,ksoilmax))
    allocate(tsoildeep(i2,j2))
    allocate(phitot(i2,j2))

    ! 1.2   -  Initialize arrays
    ! First test, pick ECMWF config
    dzsoil(1) = 0.07
    dzsoil(2) = 0.21
    dzsoil(3) = 0.72
    dzsoil(4) = 1.89

    !! 1.3   -  Calculate vertical layer properties
    zsoil(1)  = dzsoil(1)
    do k = 2, ksoilmax
      zsoil(k) = zsoil(k-1) + dzsoil(k)
    end do
    zsoilc = -(zsoil-0.5*dzsoil)
    do k = 1, ksoilmax-1
      dzsoilh(k) = 0.5 * (dzsoil(k+1) + dzsoil(k))
    end do
    dzsoilh(ksoilmax) = 0.5 * dzsoil(ksoilmax)

    phitot = 0.0
    ! Calculate conductivity saturated soil
    lambdasat = lambdasm ** (1. - phi) * lambdaw ** (phi)

    ! 2.1  -   Allocate arrays
    allocate(Qnet(i2,j2))
    allocate(LE(i2,j2))
    allocate(H(i2,j2))
    allocate(G0(i2,j2))
    allocate(CO2flux(i2,j2))

    allocate(rsveg(i2,j2))
    allocate(rsmin(i2,j2))
    allocate(rssoil(i2,j2))
    allocate(rssoilmin(i2,j2))
    allocate(cveg(i2,j2))
    allocate(cliq(i2,j2))
    allocate(tendskin_surf(i2,j2))
    allocate(tskinm_surf(i2,j2))
    allocate(Cskin(i2,j2))
    allocate(lambdaskin(i2,j2))
    allocate(LAI_surf(i2,j2))
    allocate(gD(i2,j2))
    allocate(Wl(i2,j2))
    allocate(Wlm(i2,j2))

    if(lhetero) then
      do j=1,j2
        tempy=patchynr(j)
        do i=1,i2
          tempx=patchxnr(i)

          phiw( i,j,:)   = phiw_patch( :,  tempx,tempy)
          rootf(i,j,:)   = rootf_patch(:,  tempx,tempy)
          tsoil(i,j,:)   = tsoil_patch(:,  tempx,tempy)
          tsoildeep(i,j) = tsoildeep_patch(tempx,tempy)

          Qnet       (i,j) = Qnet_patch      (tempx,tempy)
          Cskin      (i,j) = Cskin_patch     (tempx,tempy)
          lambdaskin (i,j) = lambdaskin_patch(tempx,tempy)
          rsmin      (i,j) = rsmin_patch     (tempx,tempy)
          rssoilmin  (i,j) = rsmin_patch     (tempx,tempy)
          LAI_surf        (i,j) = LAI_patch       (tempx,tempy)
          gD         (i,j) = gD_patch        (tempx,tempy)
          cveg       (i,j) = cveg_patch      (tempx,tempy)
          Wl         (i,j) = Wl_patch        (tempx,tempy)
        enddo
      enddo

      do k = 1, ksoilmax
        phitot(:,:) = phitot(:,:) + rootf(:,:,k)*phiw(:,:,k)
      end do

      do k = 1, ksoilmax
        phifrac(:,:,k) = rootf(:,:,k)*phiw(:,:,k) / phitot(:,:)
      end do

    else
      ! 1.4   -   Set evaporation related properties
      ! Set water content of soil - constant in this scheme
      phiw(:,:,1) = phiwav(1)
      phiw(:,:,2) = phiwav(2)
      phiw(:,:,3) = phiwav(3)
      phiw(:,:,4) = phiwav(4)

      do k = 1, ksoilmax
        phitot(:,:) = phitot(:,:) + rootfav(k)*phiw(:,:,k)
      end do

      do k = 1, ksoilmax
        phifrac(:,:,k) = rootfav(k)*phiw(:,:,k) / phitot(:,:)
      end do

      ! Set root fraction per layer for short grass
      rootf(:,:,1) = rootfav(1)
      rootf(:,:,2) = rootfav(2)
      rootf(:,:,3) = rootfav(3)
      rootf(:,:,4) = rootfav(4)

      tsoil(:,:,1)   = tsoilav(1)
      tsoil(:,:,2)   = tsoilav(2)
      tsoil(:,:,3)   = tsoilav(3)
      tsoil(:,:,4)   = tsoilav(4)
      tsoildeep(:,:) = tsoildeepav

      ! 2    -   Initialize land surface
      Qnet       = Qnetav
      Cskin      = Cskinav
      lambdaskin = lambdaskinav
      rsmin      = rsminav
      rssoilmin  = rssoilminav
      LAI_surf        = LAI_surfav
      gD         = gDav
      cveg       = cvegav
      Wl         = Wlav
    endif
    cliq       = 0.
    

  end subroutine initlsm


!> Calculates surface resistance, temperature and moisture using the Land Surface Model
  subroutine do_lsm

    use modglobal, only : pref0,boltz,cp,rd,rhow,rlv,i1,j1,rdt,ijtot,rk3step,nsv,xtime,rtimee,xday,xlat,xlon
    use modfields, only : ql0,qt0,thl0,rhof,presf,svm
    use modraddata,only : iradiation,useMcICA,swd,swu,lwd,lwu,irad_par,swdir,swdif,zenith,albedo_rad,tskin_rad
    use modmpi, only :comm3d,my_real,mpi_sum,mpierr,mpi_integer,myid
    use modmicrodata, only : imicro,imicro_bulk
    use modcanopy, only : canopyeb,lcanopyeb,tleaf_old_set,cican_old_set,gccan_old_set,lrelaxgc_can,lrelaxci_can

    real     :: f1, f2, f3, f4 ! Correction functions for Jarvis-Stewart
    integer  :: i, j, k, itg
    integer  :: patchx, patchy
    real     :: rk3coef,thlsl

    real     :: swdav, swuav, lwdav, lwuav
    real     :: exner, exnera, tsurfm, Tatm, e,esat, qsat, desatdT, dqsatdT, Acoef, Bcoef
    real     :: fH, fLE, fLEveg, fLEsoil, fLEliq, LEveg, LEsoil, LEliq
    real     :: Wlmx

    real     :: CO2comp, fmin, Ds, D0, co2abs, ci, fstr, Am, Rdark, alphac !Variables for AGS
    real     :: PAR, tempy, AGSa1, Dstar !Variables for AGS 1-leaf upscaling
    real     :: An, gcco2,rsAgs, rsCO2 !Variables for AGS
    real     :: fw, Resp, wco2 !Variables for AGS
 
    real     :: Fshad, gshad
    real     :: Fsun , gsun
    real     :: Fleafsun(nangle_gauss),gleafsun(nangle_gauss)
    real     :: Fnet(nz_gauss), gnet(nz_gauss)
    integer  :: angle
    ! vars needed for canopyeb
    real     :: fSL_bot, rs_leafshad_bot,rs_leafsun_bot,Fco2_can_bot

    real     :: lthls_patch(xpatches,ypatches)
    integer  :: Npatch(xpatches,ypatches), SNpatch(xpatches,ypatches)

    real     :: local_wco2av
    real     :: local_Anav
    real     :: local_gcco2av
    real     :: local_alb_canav
    real     :: local_Respav
    
    
    patchx = 0
    patchy = 0

    ! 1.X - Compute water content per layer
    do j = 2,j1
      do i = 2,i1
        phitot(i,j) = 0.0
        do k = 1, ksoilmax
          phitot(i,j) = phitot(i,j) + rootf(i,j,k) * max(phiw(i,j,k),phiwp)
        end do

        do k = 1, ksoilmax
          phifrac(i,j,k) = rootf(i,j,k) * max(phiw(i,j,k),phiwp) / phitot(i,j)
        end do
      end do
    end do

    thlsl = 0.0
    if(lhetero) then
      lthls_patch = 0.0
      Npatch      = 0
    endif

    wco2av       = 0.0
    Anav         = 0.0
    gcco2av      = 0.0
    alb_canav    = 0.0
    Respav       = 0.0
    local_wco2av = 0.0
    local_Anav   = 0.0
    local_gcco2av= 0.0
    local_alb_canav= 0.0
    local_Respav = 0.0

    if (lrsAgs) then
      AnField    = 0.0
      gcco2Field = 0.0
      RespField  = 0.0
      wco2Field  = 0.0
      rsco2Field = 0.0
      fstrField  = 0.0
      ciField    = 0.0
      PARField   = 0.0
      if (lsplitleaf) then
        PARdirField= 0.0
        PARdifField= 0.0
      endif
    endif

    rk3coef = rdt / (4. - dble(rk3step))

    do j = 2, j1
      do i = 2, i1
        if(lhetero) then
          patchx = patchxnr(i)
          patchy = patchynr(j)
        endif

        ! 1.2   -   Calculate the skin temperature as the top boundary conditions for heat transport
        if(iradiation > 0) then
          if(iradiation == 1 .and. useMcICA) then
            if(rk3step == 1) then
              swdavn(i,j,2:nradtime) = swdavn(i,j,1:nradtime-1)
              swuavn(i,j,2:nradtime) = swuavn(i,j,1:nradtime-1)
              lwdavn(i,j,2:nradtime) = lwdavn(i,j,1:nradtime-1)
              lwuavn(i,j,2:nradtime) = lwuavn(i,j,1:nradtime-1)

              swdavn(i,j,1) = swd(i,j,1)
              swuavn(i,j,1) = swu(i,j,1)
              lwdavn(i,j,1) = lwd(i,j,1)
              lwuavn(i,j,1) = lwu(i,j,1)

            end if

            swdav = sum(swdavn(i,j,:)) / nradtime
            swuav = sum(swuavn(i,j,:)) / nradtime
            lwdav = sum(lwdavn(i,j,:)) / nradtime
            lwuav = sum(lwuavn(i,j,:)) / nradtime

            Qnet(i,j) = -(swdav + swuav + lwdav + lwuav)
          elseif(iradiation == irad_par .or. iradiation == 10) then !  Delta-eddington approach (2)  .or. rad_user (10)
            swdav      = -swd(i,j,1)
            Qnet(i,j)  = (swd(i,j,1) - swu(i,j,1) + lwd(i,j,1) - lwu(i,j,1))
          else ! simple radiation scheme and RRTMG
            Qnet(i,j) = -(swd(i,j,1) + swu(i,j,1) + lwd(i,j,1) + lwu(i,j,1))
            swdav     = swd(i,j,1)
          end if
        else
          if(lhetero) then
            Qnet(i,j) = Qnet_patch(patchx,patchy)
          else
            Qnet(i,j) = Qnetav
          endif
        end if

        ! 2.1   -   Calculate the surface resistance
        if (.not. lrsAgs) then
           ! Stomatal opening as a function of incoming short wave radiation
           if (iradiation > 0) then
             f1  = 1. / min(1., (0.004 * max(0.,-swdav) + 0.05) / (0.81 * (0.004 * max(0.,-swdav) + 1.)))
           else
             f1  = 1.
           end if
 
           ! Soil moisture availability
           f2  = (phifc - phiwp) / (phitot(i,j) - phiwp)
           ! Prevent f2 becoming less than 1
           f2  = max(f2, 1.)
           ! Put upper boundary on f2 for cases with very dry soils
           f2  = min(1.e8, f2)
 
           ! Response of stomata to vapor deficit of atmosphere
           esat = 0.611e3 * exp(17.2694 * (thl0(i,j,1) - 273.16) / (thl0(i,j,1) - 35.86))
           if(lhetero) then
             e    = qt0(i,j,1) * ps_patch(patchx,patchy) / 0.622
           else
             e    = qt0(i,j,1) * ps / 0.622
           endif
 
           f3   = 1. / exp(-gD(i,j) * (esat - e) / 100.)
 
           ! Response to temperature
           exnera  = (presf(1) / pref0) ** (rd/cp)
           Tatm    = exnera * thl0(i,j,1) + (rlv / cp) * ql0(i,j,1)
           f4      = 1./ (1. - 0.0016 * (298.0 - Tatm) ** 2.)
 
           rsveg(i,j)  = rsmin(i,j) / LAI_surf(i,j) * f1 * f2 * f3! * f4 Not considered anymore
 
 
        else !(lrsAgs) then
         ! 2.1a  - Recalculate vegetation resistance using AGS
          if (.not. linags) then !initialize AGS
            if(nsv .le. 0) then
              if (myid == 0) then
                print *, 'Problem in namoptions NAMSURFACE'
                print *, 'You enabled AGS (with switch lrsAgs), but there are no scalars (and thus no CO2 as needed for AGS) '
                stop 'ERROR: Problem in namoptions NAMSURFACE - AGS'
              endif
            endif
            if(lCHon) then !Chemistry is on
              if (CO2loc .lt. 1) then !No CO2 in chemistry
                if (myid == 0) then
                  print *, 'WARNING ::: There is no CO2 defined in the chemistry scheme'
                  print *, 'WARNING ::: Scalar 1 might be considered to be CO2 '
                  stop 'ERROR: Problem in namoptions NAMSURFACE - AGS'
                endif
                indCO2 = 1
              else  !CO2 present in chemistry
                indCO2 = CO2loc
              endif !Is CO2 present?
            else if (imicro==imicro_bulk) then !chemistry off and bulk_microphysics on
              if (myid==0) then
                print *,'WARNING ::: bulk microphysics and AGS are both ON'
                print *,'WARNING ::: Scalar 1 and 2 are considered qr and Nr,respectively for microphysics scheme'
                print *,'WARNING ::: Scalar 3 is considered CO2 for A-gs'
              endif
              indCO2 = 3
            else !Chemistry and bulk_micro are off
              if (myid == 0) then
                print *, 'WARNING ::: There is no CO2 defined due to the absence of a chemistry scheme'
                print *, 'WARNING ::: Scalar 1 is considered to be CO2 '
              endif
              indCO2 = 1
            endif !Is chemistry or bulk_micro on?
            linags = .true.
          
          endif !linags
          if (lsplitleaf) then
            PARdir_TOV = 0.5 * max(0.1,abs(swdir(i,j,1)))
            PARdif_TOV = 0.5 * max(0.1,abs(swdif(i,j,1)))
           !call canopyrad(nz_gauss,LAI_surf(i,j),LAI_surf(i,j)*LAI_g,PARdir_TOV,PARdif_TOV,albedo_surf(i,j),1.0,& ! in! 
           !     PARleaf_shad,PARleaf_sun,fSL,& 
           !     albdir_lsplit(i,j),albdif_lsplit(i,j),albswd_lsplit(i,j),&
           !     PARdir_lsplit(:nz_gauss),PARdif_lsplit(:nz_gauss),PARu_lsplit(:nz_gauss))! couldbe used for radiation
            !assume SW = 2.0*PAR
            swdir_lsplit(i,j,:nz_gauss) = 2.0 * PARdir_lsplit(:nz_gauss)
            swdif_lsplit(i,j,:nz_gauss) = 2.0 * PARdif_lsplit(:nz_gauss)
            swu_lsplit  (i,j,:nz_gauss) = 2.0 * PARu_lsplit  (:nz_gauss)
            do itg = 1,nz_gauss
              !shaded
              call f_Ags(svm(i,j,1,indCO2),qt0(i,j,1),rhof(1),thl0(i,j,1),ps,tskin_surf(i,j),  & ! in
                         phitot(i,j),PARleaf_shad(itg), & ! in 
                         lrelaxgc_surf,gcsurf_old_set,kgc_surf,gshad_old(i,j,itg),rk3coef, & ! in
                         lrelaxci_surf,cisurf_old_set,kci_surf,ci_old(i,j), & ! in
                         gshad,Fshad,ci,&                                  !out
                         fstr,Am,Rdark,alphac,co2abs,CO2comp,Ds,D0,fmin)   !out
              !sunny
              if (l3leaves) then      ! 3 angles for sunny leaves
                do angle=1,nangle_gauss
                  call f_Ags(svm(i,j,1,indCO2),qt0(i,j,1),rhof(1),thl0(i,j,1),ps,tskin_surf(i,j), & ! in
                             phitot(i,j),PARleaf_sun(itg,angle),  & ! in
                             lrelaxgc_surf,gcsurf_old_set,kgc_surf,gleafsun_old(i,j,itg,angle),rk3coef, & ! in
                             lrelaxci_surf,cisurf_old_set,kci_surf,ci_old(i,j), & ! in
                             gleafsun(angle),Fleafsun(angle),ci,                &   !out
                             fstr,Am,Rdark,alphac,co2abs,CO2comp,Ds,D0,fmin) !out, not needed here
                end do
                if (lrelaxgc_surf) then
                  if (gcsurf_old_set .and. rk3step ==3) then
                    gshad_old(i,j,itg) = gshad
                    gleafsun_old(i,j,itg,:) = gleafsun(:)
                  else if (.not. gcsurf_old_set)then
                    gshad_old(i,j,itg) = gshad
                    gleafsun_old(i,j,itg,:) = gleafsun(:)
                  endif
                endif
                Fsun   = sum(weight_g * Fleafsun(1:nangle_gauss))
                gsun   = sum(weight_g * gleafsun(1:nangle_gauss))
              else ! angles PAR are averaged
                PARleaf_allsun   = sum(weight_g * PARleaf_sun(itg,1:nangle_gauss))
                call f_Ags(svm(i,j,1,indCO2),qt0(i,j,1),rhof(1),thl0(i,j,1),ps,tskin_surf(i,j), & ! in
                           phitot(i,j),PARleaf_allsun(itg), & ! in
                           lrelaxgc_surf,gcsurf_old_set,kgc_surf,gsun_old(i,j,itg),rk3coef,& !
                           lrelaxci_surf,cisurf_old_set,kci_surf,ci_old(i,j),& !
                           gsun,Fsun,ci, &
                           fstr,Am,Rdark,alphac,co2abs,CO2comp,Ds,D0,fmin)
                if (lrelaxgc_surf) then
                  if (gcsurf_old_set .and. rk3step ==3) then
                    gshad_old(i,j,itg) = gshad
                    gsun_old(i,j,itg) = gsun
                  else if (.not. gcsurf_old_set) then
                    gshad_old(i,j,itg) = gshad
                    gsun_old(i,j,itg) = gsun
                  endif
                endif
              end if ! l3leaves
              Fnet(itg)  = Fsun * fSL(itg) + Fshad * (1 - fSL(itg))
              gnet(itg)  = gsun * fSL(itg) + gshad * (1 - fSL(itg))
            end do
          
            An       = LAI_surf(i,j) * sum(weight_g * Fnet) ! temporary An
            gcco2    = LAI_surf(i,j) * sum(weight_g * gnet)
            if (lrelaxci_surf) then
              if (cisurf_old_set .and. rk3step ==3) then
                ci_old(i,j) = ci
              else if (.not. gcsurf_old_set)then
                ci_old(i,j) = ci
              endif
            endif
          else ! lsplitleaf
            if (lcanopyeb) then
            ! move to the canopy module and rewrite ,among others,swd modified by canopy and needed for surface
              call canopyeb(i,j,ps,rk3coef)           ! in
            endif ! lcanopyeb  
             ! and for understory vegetation:
            
            !upscaling following Ronda et al
            PAR      = 0.50 * max(0.1,abs(swd(i,j,1))) !
            call f_Ags(svm(i,j,1,indCO2),qt0(i,j,1),rhof(1),thl0(i,j,1),ps,tskin_surf(i,j),& ! in
                       phitot(i,j),PAR, & ! in
                       lrelaxgc_surf,gcsurf_old_set,kgc_surf,gc_old(i,j),rk3coef,   & ! in
                       lrelaxci_surf,cisurf_old_set,kci_surf,ci_old(i,j),           & ! in
                       gshad,Fshad,ci, & ! first 2 are irrelevant here
                       fstr,Am,Rdark,alphac,co2abs,CO2comp,Ds,D0,fmin) ! out
          ! Calculate upscaling from leaf to canopy: net flow  CO2 into the plant (An)
            AGSa1    = 1.0 / (1 - f0)
            Dstar    = D0 / (AGSa1 * (f0 - fmin))
            
            tempy    = alphac * Kx * PAR / (Am + Rdark)
            An       = (Am + Rdark) * (1 - 1.0 / (Kx *  LAI_surf(i,j)) * (E1(tempy * exp(-Kx*LAI_surf(i,j))) - E1(tempy)))
            gc_inf    = LAI_surf(i,j) * (gmin/nuco2q + AGSa1 * fstr * An / ((co2abs - CO2comp) * (1 + Ds / Dstar)))
            if (lrelaxgc_surf) then
              if (gcsurf_old_set) then
                gcco2       = gc_old(i,j) + min(kgc_surf*rk3coef, 1.0) * (gc_inf - gc_old(i,j))
                if (rk3step ==3) then
                  gc_old(i,j) = gcco2
                endif
              else
                gcco2 = gc_inf
                gc_old(i,j) = gcco2
              endif
            else
              gcco2 = gc_inf
            endif

            if (lrelaxci_surf) then
              if (cisurf_old_set .and. rk3step ==3) then
                ci_old(i,j) = ci
              else if (.not. cisurf_old_set) then
                ci_old(i,j) = ci
              endif
            endif !lrelaxci_surf  

          end if ! splitleaf
         

          ! Calculate surface resistances for moisture and carbon dioxide
          rsAgs    = 1.0 / (nuco2q * gcco2)
          rsCO2    = 1.0 / gcco2
          
          ! Calculate net flux of CO2 into the plant (An)
          An       = - (co2abs - ci) / (ra(i,j) + rsCO2)

          rsveg(i,j) = rsAgs

          ! CO2 soil respiraion surface flux
          fw       = Cw * wsmax / (phitot(i,j) + wsmin)

!          Resp     = R10 * (1 - fw)*(1+ustar(i,j)) * exp( Eact0 / (283.15 * 8.314) * (1.0 - 283.15 / ( thl0(i,j,1) )))
          Resp     = R10 * (1 - fw)* exp( Eact0 / (283.15 * 8.314) * (1.0 - 283.15 / ( tsoil(i,j,1) )))

          wco2     = (An + Resp) * (MW_Air/MW_CO2) * (1.0/rhof(1)) ! In ppm m/s

          CO2flux(i,j) = wco2 * 1000.0 ! In ppb m/s


          local_wco2av = local_wco2av + wco2
          local_Anav   = local_Anav   + An
          local_gcco2av= local_gcco2av   + gcco2
          local_alb_canav= local_alb_canav   + albedo_rad(i,j)
          local_Respav = local_Respav + Resp

          AnField   (i,j) = An
          gcco2Field(i,j) = gcco2
          RespField (i,j) = Resp
          wco2Field (i,j) = wco2
          rsco2Field(i,j) = rsCO2
          fstrField (i,j) = fstr
          ciField   (i,j) = ci
          PARField  (i,j) = PAR

        endif !lrsAgs
        
        if (lcanopyeb) then ! update surface Qnet if canopy above is present
          if(iradiation > 0) then
            if(iradiation == 1 .and. useMcICA) then
              if(rk3step == 1) then
                swdavn(i,j,2:nradtime) = swdavn(i,j,1:nradtime-1)
                swuavn(i,j,2:nradtime) = swuavn(i,j,1:nradtime-1)
                lwdavn(i,j,2:nradtime) = lwdavn(i,j,1:nradtime-1)
                lwuavn(i,j,2:nradtime) = lwuavn(i,j,1:nradtime-1)
         
                swdavn(i,j,1) = swd(i,j,1)
                swuavn(i,j,1) = swu(i,j,1)
                lwdavn(i,j,1) = lwd(i,j,1)
                lwuavn(i,j,1) = lwu(i,j,1)
         
              end if
         
              swdav = sum(swdavn(i,j,:)) / nradtime
              swuav = sum(swuavn(i,j,:)) / nradtime
              lwdav = sum(lwdavn(i,j,:)) / nradtime
              lwuav = sum(lwuavn(i,j,:)) / nradtime
         
              Qnet(i,j) = -(swdav + swuav + lwdav + lwuav)
            elseif(iradiation == irad_par .or. iradiation == 10) then !  Delta-eddington approach (2)  .or. rad_user (10)
              swdav      = -swd(i,j,1)
              Qnet(i,j)  = (swd(i,j,1) - swu(i,j,1) + lwd(i,j,1) - lwu(i,j,1))
            else ! simple radiation scheme and RRTMG
              Qnet(i,j) = -(swd(i,j,1) + swu(i,j,1) + lwd(i,j,1) + lwu(i,j,1))
              swdav     = swd(i,j,1)
            end if
          else
            if(lhetero) then
              Qnet(i,j) = Qnet_patch(patchx,patchy)
            else
              Qnet(i,j) = Qnetav
            endif
          end if
        endif

        ! 2.2   - Calculate soil resistance based on ECMWF method

        f2  = (phifc - phiwp) / (phiw(i,j,1) - phiwp)
        f2  = max(f2, 1.)
        f2  = min(1.e8, f2)
        rssoil(i,j) = rssoilmin(i,j) * f2
        ! 1.1   -   Calculate the heat transport properties of the soil
        ! CvH I put it in the init function, as we don't have prognostic soil moisture at this stage

        ! CvH solve the surface temperature implicitly including variations in LWout
        if(rk3step == 1) then
          tskinm_surf(i,j) = tskin_surf(i,j)
          Wlm(i,j)    = Wl(i,j)
        end if

        if(lhetero) then
          exner   = (ps_patch(patchx,patchy) / pref0) ** (rd/cp)
        else
          exner   = (ps / pref0) ** (rd/cp)
        endif
        tsurfm  = tskinm_surf(i,j) * exner

        esat    = 0.611e3 * exp(17.2694 * (tsurfm - 273.16) / (tsurfm - 35.86))
        if(lhetero) then
          qsat    = 0.622 * esat / ps_patch(patchx,patchy)
        else
          qsat    = 0.622 * esat / ps
        endif
        desatdT = esat * (17.2694 / (tsurfm - 35.86) - 17.2694 * (tsurfm - 273.16) / (tsurfm - 35.86)**2.)
        if(lhetero) then
          dqsatdT = 0.622 * desatdT / ps_patch(patchx,patchy)
        else
          dqsatdT = 0.622 * desatdT / ps
        endif

        ! First, remove LWup from Qnet calculation
        Qnet(i,j) = Qnet(i,j) + boltz * tsurfm ** 4.

        ! Calculate coefficients for surface fluxes
        fH      = rhof(1) * cp / ra(i,j)

        ! Allow for dew fall
        if(qsat - qt0(i,j,1) < 0.) then
          rsveg(i,j)  = 0.
          rssoil(i,j) = 0.
        end if

        Wlmx      = LAI_surf(i,j) * Wmax
        Wl(i,j)   = min(Wl(i,j), Wlmx)
        cliq(i,j) = Wl(i,j) / Wlmx

        fLEveg  = (1. - cliq(i,j)) * cveg(i,j) * rhof(1) * rlv / (ra(i,j) + rsveg(i,j))
        fLEsoil = (1. - cveg(i,j))             * rhof(1) * rlv / (ra(i,j) + rssoil(i,j))
        fLEliq  = cliq(i,j) * cveg(i,j)        * rhof(1) * rlv /  ra(i,j)

        fLE     = fLEveg + fLEsoil + fLEliq

        exnera  = (presf(1) / pref0) ** (rd/cp)
        Tatm    = exnera * thl0(i,j,1) + (rlv / cp) * ql0(i,j,1)

        Acoef   = Qnet(i,j) - boltz * tsurfm ** 4. + 4. * boltz * tsurfm ** 4. + fH * Tatm + fLE *&
        (dqsatdT * tsurfm - qsat + qt0(i,j,1)) + lambdaskin(i,j) * tsoil(i,j,1)
!\todo  Acoef   = Qnet(i,j) - boltz * tsurfm ** 4. + 4. * boltz * tsurfm ** 4. + fH * Tatm + fLE *&
!       (dqsatdT * tsurfm - qsat + qt0(i,j,1)) + lambdaskin(i,j) * tsoil(i,j,1)- fRs[t]*(1.0 - albedoav_surf(i,j))*swdown
        Bcoef   = 4. * boltz * tsurfm ** 3. + fH + fLE * dqsatdT + lambdaskin(i,j)

        if (Cskin(i,j) == 0.) then
          tskin_surf(i,j) = Acoef * Bcoef ** (-1.) / exner
        else
          tskin_surf(i,j) = (1. + rk3coef / Cskin(i,j) * Bcoef) ** (-1.) * (tsurfm + rk3coef / Cskin(i,j) * Acoef) / exner
        end if

        Qnet(i,j)     = Qnet(i,j) - (boltz * tsurfm ** 4. + 4. * boltz * tsurfm ** 3. * (tskin_surf(i,j) * exner - tsurfm))
        G0(i,j)       = lambdaskin(i,j) * ( tskin_surf(i,j) * exner - tsoil(i,j,1) )
        LE(i,j)       = - fLE * ( qt0(i,j,1) - (dqsatdT * (tskin_surf(i,j) * exner - tsurfm) + qsat))

        LEveg         = - fLEveg  * ( qt0(i,j,1) - (dqsatdT * (tskin_surf(i,j) * exner - tsurfm) + qsat))
        LEsoil        = - fLEsoil * ( qt0(i,j,1) - (dqsatdT * (tskin_surf(i,j) * exner - tsurfm) + qsat))
        LEliq         = - fLEliq  * ( qt0(i,j,1) - (dqsatdT * (tskin_surf(i,j) * exner - tsurfm) + qsat))

        if(LE(i,j) == 0.) then
          rs(i,j)     = 1.e8
        else
          rs(i,j)     = - rhof(1) * rlv * (qt0(i,j,1) - (dqsatdT * (tskin_surf(i,j) * exner - tsurfm) + qsat)) / LE(i,j) - ra(i,j)
        end if

        H(i,j)        = - fH  * ( Tatm - tskin_surf(i,j) * exner )
        tskin_surf(i,j)    = max(min(tskin_surf(i,j),tskinm_surf(i,j)+10.),tskinm_surf(i,j)-10.)
        tendskin_surf(i,j) = Cskin(i,j) * (tskin_surf(i,j) - tskinm_surf(i,j)) * exner / rk3coef

        ! In case of dew formation, allow all water to enter skin reservoir Wl
        if(qsat - qt0(i,j,1) < 0.) then
          Wl(i,j)       =  Wlm(i,j) - rk3coef * ((LEliq + LEsoil + LEveg) / (rhow * rlv))
        else
          Wl(i,j)       =  Wlm(i,j) - rk3coef * (LEliq / (rhow * rlv))
        end if

        thlsl = thlsl + tskin_surf(i,j)
        if (lhetero) then
          lthls_patch(patchx,patchy) = lthls_patch(patchx,patchy) + tskin_surf(i,j)
          Npatch(patchx,patchy)      = Npatch(patchx,patchy)      + 1
        endif

        ! Solve the soil
        if(rk3step == 1) then
          tsoilm(i,j,:) = tsoil(i,j,:)
          phiwm(i,j,:)  = phiw(i,j,:)
        end if

        ! Calculate the soil heat capacity and conductivity based on water content
        do k = 1, ksoilmax
          pCs(i,j,k)    = (1. - phi) * pCm + phiw(i,j,k) * pCw
          Ke            = log10(phiw(i,j,k) / phi) + 1.
          lambda(i,j,k) = Ke * (lambdasat - lambdadry) + lambdadry
        end do

        do k = 1, ksoilmax-1
          lambdah(i,j,k) = (lambda(i,j,k) * dzsoil(k+1) + lambda(i,j,k+1) * dzsoil(k)) / (dzsoil(k+1)+dzsoil(k))
        end do

        lambdah(i,j,ksoilmax) = lambda(i,j,ksoilmax)

        do k = 1, ksoilmax
          gammas(i,j,k)  = gammasat * (phiw(i,j,k) / phi) ** (2. * bc + 3.)
          lambdas(i,j,k) = bc * gammasat * (-1.) * psisat / phi * (phiw(i,j,k) / phi) ** (bc + 2.)
        end do

        do k = 1, ksoilmax-1
          lambdash(i,j,k) = (lambdas(i,j,k) * dzsoil(k+1) + lambdas(i,j,k+1) * dzsoil(k)) / (dzsoil(k+1)+dzsoil(k))
          gammash(i,j,k)  = (gammas(i,j,k)  * dzsoil(k+1) + gammas(i,j,k+1)  * dzsoil(k)) / (dzsoil(k+1)+dzsoil(k))
        end do

        lambdash(i,j,ksoilmax) = lambdas(i,j,ksoilmax)

        ! 1.4   -   Solve the diffusion equation for the heat transport
        tsoil(i,j,1) = tsoilm(i,j,1) + rk3coef / pCs(i,j,1) * ( lambdah(i,j,1) &
        * (tsoil(i,j,2) - tsoil(i,j,1)) / dzsoilh(1) + G0(i,j) ) / dzsoil(1)
        do k = 2, ksoilmax-1
          tsoil(i,j,k) = tsoilm(i,j,k) + rk3coef / pCs(i,j,k) * ( lambdah(i,j,k) * (tsoil(i,j,k+1) - tsoil(i,j,k))&
          / dzsoilh(k) - lambdah(i,j,k-1) * (tsoil(i,j,k) - tsoil(i,j,k-1)) / dzsoilh(k-1) ) / dzsoil(k)
        end do
        tsoil(i,j,ksoilmax) = tsoilm(i,j,ksoilmax) + rk3coef / pCs(i,j,ksoilmax) * ( lambda(i,j,ksoilmax) * &
        (tsoildeep(i,j) - tsoil(i,j,ksoilmax)) / dzsoil(ksoilmax) - lambdah(i,j,ksoilmax-1) * &
        (tsoil(i,j,ksoilmax) - tsoil(i,j,ksoilmax-1)) / dzsoil(ksoilmax-1) ) / dzsoil(ksoilmax)
        ! 1.5   -   Solve the diffusion equation for the moisture transport
        phiw(i,j,1) = phiwm(i,j,1) + rk3coef * ( lambdash(i,j,1) * (phiw(i,j,2) - phiw(i,j,1)) / &
        dzsoilh(1) - gammash(i,j,1) - (phifrac(i,j,1) * LEveg + LEsoil) / (rhow*rlv)) / dzsoil(1)
        do k = 2, ksoilmax-1
          phiw(i,j,k) = phiwm(i,j,k) + rk3coef * ( lambdash(i,j,k) * (phiw(i,j,k+1) - phiw(i,j,k)) / &
          dzsoilh(k) - gammash(i,j,k) - lambdash(i,j,k-1) * (phiw(i,j,k) - phiw(i,j,k-1)) / dzsoilh(k-1) + &
          gammash(i,j,k-1) - (phifrac(i,j,k) * LEveg) / (rhow*rlv)) / dzsoil(k)
        end do
        ! closed bottom for now
        phiw(i,j,ksoilmax) = phiwm(i,j,ksoilmax) + rk3coef * (- lambdash(i,j,ksoilmax-1) * &
        (phiw(i,j,ksoilmax) - phiw(i,j,ksoilmax-1)) / dzsoil(ksoilmax-1) + gammash(i,j,ksoilmax-1) &
        - (phifrac(i,j,ksoilmax) * LEveg) / (rhow*rlv) ) / dzsoil(ksoilmax)
   
      end do
    end do

    if (lrelaxgc_surf .and. (.not. gcsurf_old_set) ) then
      if (rk3step == 3) then
        gcsurf_old_set = .true.
      endif
    endif

    if (lrelaxci_surf .and. (.not. cisurf_old_set) ) then
      if (rk3step == 3) then
        cisurf_old_set = .true.
      endif
    endif
    if (lcanopyeb) then
       ! switches of canopyeb
      if (lrelaxgc_can .and. (.not. gccan_old_set) ) then
        if (rk3step == 3) then
          gccan_old_set = .true.
        endif
      endif
      if (lrelaxci_can .and. (.not. cican_old_set) ) then
        if (rk3step == 3) then
          cican_old_set = .true.
        endif
      endif
      if (.not. tleaf_old_set) then
        if (rk3step == 3) then
          tleaf_old_set = .true.
          if (myid==0)print *,'XPB, tleaf_old_set to true'
        endif
      endif
    endif

    call MPI_ALLREDUCE(local_wco2av, wco2av, 1,    MY_REAL, MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(local_Anav  , Anav  , 1,    MY_REAL, MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(local_gcco2av  , gcco2av  , 1,    MY_REAL, MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(local_alb_canav  , alb_canav  , 1,    MY_REAL, MPI_SUM, comm3d,mpierr)
    call MPI_ALLREDUCE(local_Respav, Respav, 1,    MY_REAL, MPI_SUM, comm3d,mpierr)

    Anav   = Anav/ijtot
    gcco2av= gcco2av/ijtot
    alb_canav= alb_canav/ijtot
    wco2av = wco2av/ijtot
    Respav = Respav/ijtot


    call MPI_ALLREDUCE(thlsl, thls, 1,  MY_REAL, MPI_SUM, comm3d,mpierr)
    thls = thls / ijtot
    if (lhetero) then
      call MPI_ALLREDUCE(lthls_patch(1:xpatches,1:ypatches), thls_patch(1:xpatches,1:ypatches),&
      xpatches*ypatches,     MY_REAL, MPI_SUM, comm3d,mpierr)
      call MPI_ALLREDUCE(Npatch(1:xpatches,1:ypatches)     , SNpatch(1:xpatches,1:ypatches)   ,&
      xpatches*ypatches, MPI_INTEGER ,MPI_SUM, comm3d,mpierr)
      thls_patch = thls_patch / SNpatch
    endif

    call qtsurf

  end subroutine do_lsm
end module modsurface
