!> \file modsurfdata.f90
!! Variable definitions and auxilary routines for the surface model

!>
!! Variable definitions and auxilary routines for surface model
!>
!! This routine should have no dependency on any other routine, save perhaps modglobal or modfields.
!!  \author Thijs Heus, MPI-M
!!  \todo Documentation
!!  \par Revision list
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



module modsurfdata

! implicit none

SAVE
  integer :: isurf        = -1            !<   Flag for surface parametrization

  ! Soil properties

  ! Domain-uniform properties
  integer, parameter  :: ksoilmax = 4       !<  Number of soil layers [-]

  real              :: lambdasat          !<  heat conductivity saturated soil [W/m/K]
  real              :: Ke                 !<  Kersten number [-]

  real, allocatable :: zsoil  (:)         !<  Height of bottom soil layer from surface [m]
  real, allocatable :: zsoilc (:)        !<  Height of center soil layer from surface [m]
  real, allocatable :: dzsoil (:)         !<  Depth of soil layer [m]
  real, allocatable :: dzsoilh(:)         !<  Depth of soil layer between center of layers [m]

  ! Spatially varying properties
  real, allocatable :: lambda  (:,:,:)    !<  Heat conductivity soil layer [W/m/K]
  real, allocatable :: lambdah (:,:,:)    !<  Heat conductivity soil layer half levels [W/m/K]
  real, allocatable :: lambdas (:,:,:)    !<  Soil moisture diffusivity soil layer
  real, allocatable :: lambdash(:,:,:)    !<  Soil moisture diffusivity soil half levels
  real, allocatable :: gammas  (:,:,:)    !<  Soil moisture conductivity soil layer
  real, allocatable :: gammash (:,:,:)    !<  Soil moisture conductivity soil half levels
  real, allocatable :: Dh      (:,:,:)    !<  Heat diffusivity
  real, allocatable :: phiw    (:,:,:)    !<  Water content soil matrix [-]
  real, allocatable :: phiwm   (:,:,:)    !<  Water content soil matrix previous time step [-]
  real, allocatable :: phifrac (:,:,:)    !<  Relative water content per layer [-]
  real              :: phiwav  (ksoilmax)
  real, allocatable :: phitot  (:,:)      !<  Total soil water content [-]
  real, allocatable :: pCs     (:,:,:)    !<  Volumetric heat capacity [J/m3/K]
  real, allocatable :: rootf   (:,:,:)    !<  Root fraction per soil layer [-]
  real              :: rootfav (ksoilmax)
  real, allocatable :: tsoil   (:,:,:)    !<  Soil temperature [K]
  real, allocatable :: tsoilm  (:,:,:)    !<  Soil temperature previous time step [K]
  real              :: tsoilav (ksoilmax)
  real, allocatable :: tsoildeep (:,:)    !<  Soil temperature [K]
  real              :: tsoildeepav

  real, allocatable :: swdavn  (:,:,:)
  real, allocatable :: swuavn  (:,:,:)
  real, allocatable :: lwdavn  (:,:,:)
  real, allocatable :: lwuavn  (:,:,:)

  integer           :: nradtime  = 60

  ! Soil related properties [case specific]
  real              :: phi       = 0.472  !<  volumetric soil porosity [-]
  real              :: phifc     = 0.323  !<  volumetric moisture at field capacity [-]
  real              :: phiwp     = 0.171  !<  volumetric moisture at wilting point [-]

  ! Soil related constants [adapted from ECMWF]
  real, parameter   :: pCm       = 2.19e6 !<  Volumetric soil heat capacity [J/m3/K]
  real, parameter   :: pCw       = 4.2e6  !<  Volumetric water heat capacity [J/m3/K]

  real, parameter   :: lambdadry = 0.190  !<  Heat conductivity dry soil [W/m/K]
  real, parameter   :: lambdasm  = 3.11   !<  Heat conductivity soil matrix [W/m/K]
  real, parameter   :: lambdaw   = 0.57   !<  Heat conductivity water [W/m/K]

  real, parameter   :: bc        = 6.04     !< Clapp and Hornberger non-dimensional exponent [-]
  real, parameter   :: gammasat  = 0.57e-6  !< Hydraulic conductivity at saturation [m s-1]
  real, parameter   :: psisat    = -0.388   !< Matrix potential at saturation [m]

  ! Land surface properties

  ! Surface properties
  real, allocatable :: z0m        (:,:) !<  Roughness length for momentum [m]
  real              :: z0mav    = -1
  real, allocatable :: z0h        (:,:) !<  Roughness length for heat [m]
  real              :: z0hav    = -1
  real, allocatable :: tskin_surf      (:,:) !< Surface  skin temperature [K]
  real, allocatable :: tskinm_surf     (:,:) !< Surface skin temperature previous timestep [K]
  real, allocatable :: Wl         (:,:) !<  Liquid water reservoir [m]
  real              :: Wlav     = -1
  real, parameter   :: Wmax     = 0.0002 !<  Maximum layer of liquid water on surface [m]
  real, allocatable :: Wlm        (:,:) !<  Liquid water reservoir previous timestep [m]
  real, allocatable :: qskin_surf (:,:) !<  Surface skin specific humidity [kg/kg]
  real, allocatable :: albedo_surf(:,:) !<  Surface albedo [-]
  real              :: albedoav_surf = -1
  real, allocatable :: LAI        (:,:) !<  Leaf area index understory vegetation [-]
  real              :: LAIav    = -1
  real, allocatable :: cveg       (:,:) !<  Vegetation cover [-]
  real              :: cvegav   = -1
  real, allocatable :: cliq       (:,:) !<  Fraction of vegetated surface covered with liquid water [-]
  real, allocatable :: Cskin      (:,:) !<  Heat capacity skin layer [J]
  real              :: Cskinav  = -1
  real, allocatable :: lambdaskin (:,:) !<  Heat conductivity skin layer [W/m/K]
  real              :: lambdaskinav = -1
  real              :: ps       = -1    !<  Surface pressure [Pa]

  ! AGS options (require interactive landsurface: isurf=2)
  !<Namelist options
  logical           :: lrsAgs        = .false.!<  Switch to apply AGS to calculate resistances
  logical           :: lCO2Ags       = .false.!<  Switch to calculate CO2 fluxes with AGS
  integer           :: planttype     = 3      !<  Integer to switch between (C)3 and (C)4 plants
  logical           :: lrelaxgc_surf = .false.!<  Switch to delay plant response at surface. Timescale is equal to 1/kgc_surf
  real              :: kgc_surf      = 0.00113!<  Standard stomatal response rate at surface(corresponding to a time scale of 14.75 min.) [1/s]
  logical           :: gcsurf_old_set = .false.!<  Only apply relaxing function after initial gc is calculated once for surface
  logical           :: lrelaxci_surf  = .false.!<  Switch to delay internal CO2 concentration in plant leafs; Timescale equal to that for gc
  real              :: kci_surf       = 0.00113!<  Standard internal CO2 response rate (corresponding to a time scale of 14.75 min.) [1/s]
  logical           :: cisurf_old_set = .false.!<  Only apply relaxing function after initial ci is calculated once
  real, allocatable :: gc_old       (:,:)  !<  Old value for gc
  real              :: gc_inf              !<  Attractor for stomatal response rate
  real, allocatable :: ci_old       (:,:)  !<  Old value for ci
  real              :: ci_inf              !<  Attractor for ci
  real              :: wco2av     = 0.0
  real              :: Anav       = 0.0
  real              :: gcco2av    = 0.0
  real              :: Respav     = 0.0
  !<Non namelist options
  logical           :: linags     = .false.!<  Switch to make additional initialization for AGS
  logical           :: lCHon      = .false.!<  Equal to lchem, but due to compilation has to be outside modchem.f90
  integer           :: indCO2     = -1     !<  Index of CO2 in the scalars
  integer           :: CO2loc     = -1     !<  Index of CO2 in the scalars
  real, allocatable :: CO2flux(:,:)        !<  Surface flux of CO2 as calculated by AGS

  !AGS variables
  real              :: CO2comp298 =   68.5 !<  CO2 compensation concentration
  real              :: Q10CO2     =    1.5 !<  Parameter to calculate the CO2 compensation concentration
  real              :: gm298      =    7.0 !<  Mesophyll conductance at 298 K
  real              :: Q10gm      =    2.0 !<  Parameter to calculate the mesophyll conductance
  real              :: T1gm       =  278.0 !<  Reference temperature to calculate the mesophyll conductance
  real              :: T2gm       =  301.0 !<  Reference temperature to calculate the mesophyll conductance
  real              :: gmin       = 2.5e-4 !<  Cuticular (minimum) conductance
  real              :: nuco2q     =    1.6 !<  Ratio molecular viscosity water to carbon dioxide
  real              :: f0         =   0.89 !<  Maximum value Cfrac
  real              :: ad         =   0.07 !<  Regression coefficient to calculate Cfrac
  real              :: Ammax298   =    2.2 !<  CO2 maximal primary productivity
  real              :: Q10am      =    2.0 !<  Parameter to calculate maximal primary productivity
  real              :: T1Am       =    281 !<  Reference temperature to calculate maximal primary productivity
  real              :: T2Am       =    311 !<  Reference temperature to calculate maximal primary productivity
  real              :: alpha0     =  0.017 !<  Initial low light conditions
  real              :: Kx         =    0.7 !<  Extinction coefficient PAR
  real              :: Cw         = 1.6e-3 !<  Constant water stress correction
  real              :: wsmax      =   0.55 !<  Upper reference value soil water
  real              :: wsmin      =  0.005 !<  Lower reference value soil water
  real              :: R10        =   0.23 !<  Respiration at 10oC (Jacobs 2007)
  real              :: Eact0      = 53.3e3 !<  Activation energy
  real              :: MW_Air     =  28.97 !<  Molecular weight of air
  real              :: MW_CO2     =     44 !<  Molecular weight of CO2
  real, allocatable :: wco2Field    (:,:)
  real, allocatable :: AnField      (:,:)
  real, allocatable :: gcco2Field   (:,:)
  real, allocatable :: rsco2Field   (:,:)
  real, allocatable :: RespField    (:,:)
  real, allocatable :: fstrField    (:,:)
  real, allocatable :: tauField     (:,:)
  real, allocatable :: ciField      (:,:)
  real, allocatable :: PARField     (:,:)
  real, allocatable :: PARdirField  (:,:)
  real, allocatable :: PARdifField  (:,:)

  !Variables for 2leaf AGS
  logical                   :: lsplitleaf =                  .false. !<  Switch to split AGS calculations over different parts of the leaf (direct & diffuse at different layers)
  logical                   :: l3leaves   =                  .true. !<  Switch to keep 3 leaf orientation angles on sunny leaves 
  integer,parameter         :: nz_gauss   =                        3 !<  Amount of bins to use for Gaussian integrations
  real, dimension(nz_gauss)     ::  LAI_g      = (/0.8873,   0.5,0.1127/) !<  Ratio of integrated LAI at locations where shaded leaves are evaluated in the second Gaussian integration
  integer,parameter         :: nangle_gauss =                      3 !< Amount of bins to use for Gaussian integrations on leaf angles
  real, dimension(nangle_gauss) :: weight_g   = (/0.2778,0.4444,0.2778/) !<  Weights of the Gaussian bins (must add up to 1)
  real, dimension(nangle_gauss) :: angle_g    = (/0.1127,   0.5,0.8873/) !<  Sines of the leaf angles compared to the sun in the first Gaussian integration
  real                      :: sigma      =                      0.2 !<  Scattering coefficient of leaves-controls the effective albedo
  real                      :: kdfbl      =                      0.8 !<  Diffuse radiation extinction coefficient for black leaves
  real, allocatable         :: gshad_old    (:,:,:)
  real, allocatable         :: gleafsun_old (:,:,:,:)
  real, allocatable         :: gsun_old     (:,:,:)
 
! variables for 2leaf AGS
  real,allocatable ::   PARleaf_shad   (:)    !< PAR at shaded leaves per vertical level [W/m2]
  real,allocatable ::   PARleaf_sun    (:,:)  !< PAR at sunny leaves per vertical level and leaf orientation [W/m2]
  real,allocatable ::   PARleaf_allsun (:)    !< PAR at sunny leaves per vertical level averaged over all leaf orientations [W/m2]
  real,allocatable ::   fSL            (:)    !< Fraction of sunlit leaves per evrtical level [-]
  real,allocatable ::   albdir_lsplit   (:,:)  !< effective direct SW albedo at vegetation top according to canopyrad
  real,allocatable ::   albdif_lsplit   (:,:)  !< effective diffuse SW albedo at vegetation top according to canopyrad
  real,allocatable ::   albswd_lsplit   (:,:)  !< effective global SW albedo at vegetation top according to canopyrad
  real,allocatable ::   swdir_lsplit   (:,:,:)!< swdir profile along vegetation
  real,allocatable ::   swdif_lsplit   (:,:,:)!< swdir profile along vegetation
  real,allocatable ::   swu_lsplit     (:,:,:)!< swu profile along vegetation


  ! Surface energy balance
  real, allocatable :: Qnet     (:,:)   !<  Net radiation [W/m2]
  real              :: Qnetav   = -1
  real, allocatable :: LE       (:,:)   !<  Latent heat flux [W/m2]
  real, allocatable :: H        (:,:)   !<  Sensible heat flux [W/m2]
  real, allocatable :: G0       (:,:)   !<  Ground heat flux [W/m2]
  real, allocatable :: ra       (:,:)   !<  Aerodynamic resistance [s/m]
  real, allocatable :: rs       (:,:)   !<  Composite resistance [s/m]
  real, allocatable :: rsveg    (:,:)   !<  Vegetation resistance [s/m]
  real, allocatable :: rssoil   (:,:)   !<  Soil evaporation resistance [s/m]
  real              :: rsisurf2 = 0.    !<  Vegetation resistance [s/m] if isurf2 is used
  real, allocatable :: rsmin    (:,:)   !<  Minimum vegetation resistance [s/m]
  real              :: rsminav = -1
  real, allocatable :: rssoilmin(:,:)   !<  Minimum soil evaporation resistance [s/m]
  real              :: rssoilminav = -1
  real, allocatable :: tendskin_surf (:,:)   !<  Tendency of skin [W/m2]
  real, allocatable :: gD       (:,:)   !<  Response factor vegetation to vapor pressure deficit [-]
  real              :: gDav

  ! Turbulent exchange variables
  logical           :: lmostlocal  = .false.  !<  Switch to apply MOST locally to get local Obukhov length
  logical           :: lsmoothflux = .false.  !<  Create uniform sensible and latent heat flux over domain
  logical           :: lneutral    = .false.  !<  Disable stability corrections
  real, allocatable :: obl   (:,:)      !<  Obukhov length [m]
  real              :: oblav            !<  Spatially averaged obukhov length [m]
  real, allocatable :: Cm    (:,:)      !<  Drag coefficient for momentum [-]
  real, allocatable :: Cs    (:,:)      !<  Drag coefficient for scalars [-]
  real, allocatable :: ustar (:,:)      !<  Friction velocity [m/s]
  real, allocatable :: thlflux (:,:)    !<  Kinematic temperature flux [K m/s]
  real, allocatable :: qtflux  (:,:)    !<  Kinematic specific humidity flux [kg/kg m/s]
  real, allocatable :: svflux  (:,:,:)  !<  Kinematic scalar flux [- m/s]

  ! Surface gradients of prognostic variables
  real, allocatable :: dudz  (:,:)      !<  U-wind gradient in surface layer [1/s]
  real, allocatable :: dvdz  (:,:)      !<  V-wind gradient in surface layer [1/s]
  real, allocatable :: dqtdz (:,:)      !<  Specific humidity gradient in surface layer [kg/kg/m]
  real, allocatable :: dthldz(:,:)      !<  Liquid water potential temperature gradient in surface layer [K/m]

  ! Surface properties in case of prescribed conditions (previous isurf 2, 3 and 4)
  real              :: thls  = -1       !<  Surface liquid water potential temperature [K]
  real              :: qts              !<  Surface specific humidity [kg/kg]
  real              :: thvs             !<  Surface virtual temperature [K]
  real, allocatable :: svs   (:)        !<  Surface scalar concentration [-]
  real              :: z0    = -1       !<  Surface roughness length [m]

  ! prescribed surface fluxes
  real              :: ustin  = -1      !<  Prescribed friction velocity [m/s]
  real              :: wtsurf = -1e20  !<  Prescribed kinematic temperature flux [K m/s]
  real              :: wqsurf = -1e20  !<  Prescribed kinematic moisture flux [kg/kg m/s]
  real              :: wsvsurf(100) = 0 !<  Prescribed surface scalar(n) flux [- m/s]

  ! Heterogeneous surfaces
  integer, parameter:: max_lands                   = 10 !<  Amount of land types that can be defined
  integer, parameter:: mpatch                      = 16 !<  Maximum amount of patches that can be defined in each direction
  logical           :: lhetero                 = .false.!<  Switch to apply heterogeneous surfaces using surface.inp.xxx
  logical           :: loldtable               = .false.!<  Switch to use surface.inp.xxx instead of updated surface.<name>.inp.xxx
  integer           :: xpatches                    =  2 !<  Amount of patches in the x-direction
  integer           :: ypatches                    =  1 !<  Amount of patches in the y-direction
  integer           :: land_use(mpatch,mpatch)     =  0 !<  Indicator for the land type
  integer           :: landtype(max_lands)         = -1 !< Type nr of the land in surface.inp.xxx
  character(len=10),dimension(max_lands) :: landname = "none" !< Name of the land type in surface.inp.xxx
  real              :: z0mav_land(max_lands)       = -1 !< Roughness length per land type for momentum [m]
  real              :: z0hav_land(max_lands)       = -1 !< Roughness length per land type for heat [m]
  real, allocatable :: z0mav_patch(:,:)                 !< Rougness length per patch
  real, allocatable :: z0hav_patch(:,:)                 !< Rougness length per patch
  real              :: thls_land(max_lands)        = -1 !< Surface liquid water potential temperature [K]
  real, allocatable :: thls_patch(:,:)                  !< Surface liquid water potential temperature [K]
  real, allocatable :: qts_patch(:,:)                   !< Surface liquid water potential temperature [K]
  real, allocatable :: thvs_patch(:,:)                  !< Surface virtual potential temperature [K]
  real              :: ps_land(max_lands)          = -1 !< Surface pressure [Pa]
  real, allocatable :: ps_patch(:,:)                    !< Surface pressure [Pa]
  real              :: ustin_land(max_lands)       = -1 !< Prescribed friction velocity [m/s]
  real, allocatable :: ustin_patch(:,:)                 !< Prescribed friction velocity [m/s]
  real              :: wt_land(max_lands)          = -1 !< Prescribed kinematic temperature flux [K m/s]
  real              :: wq_land(max_lands)          = -1 !< Prescribed kinematic moisture flux [kg/kg m/s]
  real              :: wsv_land(100,max_lands)     = -1 !< Prescribed surface scalar(n) flux [- m/s]
  real, allocatable :: wt_patch(:,:)                    !< Prescribed kinematic temperature flux [K m/s]
  real, allocatable :: wq_patch(:,:)                    !< Prescribed kinematic moisture flux [kg/kg m/s]
  real, allocatable :: wsv_patch(:,:,:)                 !< Prescribed surface scalar(n) flux [- m/s]
  real, allocatable :: rsisurf2_patch(:,:)              !< Vegetation resistance [s/m] if isurf2 is used
  real              :: rsisurf2_land(max_lands)    = 0  !< Vegetation resistance [s/m] if isurf2 is used
  real, allocatable :: albedo_patch(:,:)                !< Albedo
  real              :: albedo_land(max_lands)      = -1 !< Albedo
  real, allocatable :: tsoil_patch(:,:,:)               !< Soil temperature [K]
  real, allocatable :: tsoildeep_patch(:,:)             !< Soil temperature [K]
  real, allocatable :: phiw_patch(:,:,:)                !<
  real, allocatable :: rootf_patch(:,:,:)               !< Root fraction per soil layer [-]
  real, allocatable :: Cskin_patch(:,:)                 !< Heat capacity skin layer [J]
  real, allocatable :: lambdaskin_patch(:,:)            !< Heat conductivity skin layer [W/m/K]
  real, allocatable :: Qnet_patch(:,:)                  !< Net radiation [W/m2]
  real, allocatable :: cveg_patch(:,:)                  !< Vegetation cover [-]
  real, allocatable :: Wl_patch(:,:)                    !< Liquid water reservoir [m]
  real, allocatable :: rsmin_patch(:,:)                 !< Minimum vegetation resistance [s/m]
  real, allocatable :: LAI_patch(:,:)                   !< Leaf area index vegetation [-]
  real, allocatable :: gD_patch(:,:)                    !< Response factor vegetation to vapor pressure deficit [-]
  real              :: tsoil_land(ksoilmax,max_lands)=-1!< Soil temperature [K]
  real              :: tsoildeep_land(max_lands)   = -1 !< Soil temperature [K]
  real              :: phiw_land(ksoilmax,max_lands) =-1!<
  real              :: rootf_land(ksoilmax,max_lands)=-1!< Root fraction per soil layer [-]
  real              :: Cskin_land(max_lands)       = -1 !< Heat capacity skin layer [J]
  real              :: lambdaskin_land(max_lands)  = -1 !< Heat conductivity skin layer [W/m/K]
  real              :: Qnet_land(max_lands)        = -1 !< Net radiation [W/m2]
  real              :: cveg_land(max_lands)        = -1 !< Vegetation cover [-]
  real              :: Wl_land(max_lands)          = -1 !< Liquid water reservoir [m]
  real              :: rsmin_land(max_lands)       = -1 !< Minimum vegetation resistance [s/m]
  real              :: LAI_land(max_lands)         = -1 !< Leaf area index vegetation [-]
  real              :: gD_land(max_lands)          = -1 !< Response factor vegetation to vapor pressure deficit [-]
  real, allocatable :: oblpatch(:,:)                    !<  Obukhov length [m]


contains

subroutine canopyrad(layers,LAI,LAI_can,sw_dir,sw_dif,alb,               & ! in
                      Hshad,Hsun,fracSL,                                 & ! out needed for vegetation
                      effalb_dir,effalb_dif,effalb_sw,swdircan,swdifcan,swucan) ! out needed for radiation if lcanopyeb
  use modraddata , only : zenith
  use modglobal  , only : xtime,rtimee,xday,xlat,xlon
  implicit none
  
  integer,intent(in) :: layers
  real, intent(in)   :: LAI                     ! total Leaf Area Index of the whole column
  real, intent(in),dimension(layers) :: LAI_can ! array with accumulated LAI from canopy top down to evaluated height
  real, intent(in)   :: sw_dir                  ! SW direct  radition at vegetation top
  real, intent(in)   :: sw_dif                  ! SW diffuse radition at vegetation top
  real, intent(in)   :: alb                     ! ground albedo
  
  real, intent(out),dimension(layers)              :: Hshad  ! SW intercepted by shaded leaves at each layer
  real, intent(out),dimension(layers,nangle_gauss) :: Hsun   ! SW intercepted by sunlit leaves per layer and per leaf orientation
  real, intent(out),dimension(layers)              :: fracSL ! fraction of sunlit leaves per layer
  real, intent(out) ::  effalb_dir                           ! effective albedo of canopy top for direct radiation
  real, intent(out) ::  effalb_dif                           ! effective albedo of canopy top for diffuse radiation
  real, intent(out) ::  effalb_sw                            ! effective albedo of canopy top for total SW radiation
  real, intent(out), dimension(layers) :: swdircan          ! downwards direct sw inside canopy
  real, intent(out), dimension(layers) :: swdifcan          ! downwards diffuse sw inside canopy
  real, intent(out), dimension(layers) :: swucan            ! upwards (diffuse) SW inside canopy
  
  real :: PARdir_TOC,PARdif_TOC,kdrbl,kdf,kdr,iLAI
  real :: ref                    ! global PAR albedo of leave layer (smaller than sigma since some radiation is absorbed after the scattering by leaves as diffuse)
  real :: ref_dir                ! direct PAR albedo of leave layer
  real :: PARdirprof             ! profile of direct PAR inside canopy
  real :: PARdifprof             ! profile of diffuse PAR inside canopy
  real :: PARdirref_TOC          ! upwards PAR at canopy top after reflection on ground of original dir PAR
  real :: PARdifref_TOC          ! upwards PAR at canopy top after reflection on ground of original dif PAR
  
  real    :: PARdfD,PARdrD,PARdfU,PARdrU,PARdfT,PARdrT,dirPAR,difPAR,HdfT,HdrT,dirH ! see Pedruzo-Bagazgoitia et al. (2017)
  integer :: k_can
  real    :: sinbeta,minsinbeta = 1.e-10

  PARdir_TOC   = 0.50 * max(0.1,abs(sw_dir))
  PARdif_TOC   = 0.50 * max(0.1,abs(sw_dif))

  sinbeta  = max(zenith(xtime*3600 + rtimee,xday,xlat,xlon), minsinbeta)

  kdrbl    = 0.5 / sinbeta                                     ! Direct radiation extinction coefficient for black lea
  kdf      = kdfbl * sqrt(1.0-sigma)
  kdr      = kdrbl * sqrt(1.0-sigma)
  ref      = (1.0 - sqrt(1.0-sigma)) / (1.0 + sqrt(1.0-sigma)) ! Reflection coefficient
  ref_dir  = 2 * ref / (1.0 + 1.6 * sinbeta)
  do k_can = 1, layers! loop over the different LAI locations
    iLAI         = LAI_can(k_can)   ! Integrated LAI between here and canopy top
    fracSL(k_can)   = exp(-kdrbl * iLAI)      ! Fraction of sun-lit leaves
    PARdfD = PARdif_TOC * (1.0-ref)     * exp(-kdf * iLAI    )     ! Total downward PAR due to diffuse radiation at canopy top
    PARdrD = PARdir_TOC * (1.0-ref_dir) * exp(-kdr * iLAI    )     ! Total downward PAR due to direct radiation at canopy top
    PARdfU = PARdif_TOC * (1.0-ref)     * exp(-kdf * LAI) * alb * (1.0-ref) * exp(-kdf * (LAI-iLAI)) ! Total upward (reflected) PAR due to original diffuse radiation
    PARdrU = PARdir_TOC * (1.0-ref_dir) * exp(-kdr * LAI) * alb * (1.0-ref) * exp(-kdf * (LAI-iLAI)) ! Total upward (reflected) PAR due to original direct radiation
    PARdfT = PARdfD + PARdfU                                   ! Total PAR due to diffuse radiation at canopy top
    PARdrT = PARdrD + PARdrU                                   ! Total PAR due to direct radiation at canopy top
    PARdirprof = (1.0-sigma) * PARdir_TOC * fracSL(k_can)              ! Purely direct PAR (can only be downward) reaching leaves
    PARdifprof = PARdfT + PARdrT - PARdirprof                          ! Total diffuse radiation reaching leaves

    HdfT   = kdf * PARdfD + kdf * PARdfU
    HdrT   = kdr * PARdrD + kdf * PARdrU
    dirH   = kdrbl * PARdirprof
    Hshad(k_can)  = HdfT + HdrT - dirH

    Hsun(k_can,:)   = Hshad(k_can) + (angle_g * (1.0-sigma) * kdrbl * PARdir_TOC / sum(angle_g * weight_g))
 
  ! store up swdircan (downwards), swdifcan (downwards) and swucan assuming any reflected radiation by leaves goes upwards 
  ! notice that swucan+swdifcan = 2.0 * PARdifprof neglecting leave reflection/scattering coefficients
    swdircan(k_can)  = -(2.0 * PARdir_TOC * fracSL(k_can))         ! =  PARdirprof without scattering coefficient
    swdifcan(k_can)  = -(2.0 * PARdif_TOC * exp(-kdfbl * iLAI)) ! 
    !swucan = (diff and dir reflected by ground) + + (dir converted to diff) + (diff reflected upwards)
    swucan  (k_can)  = 2.0 * ((PARdfU/(1.0-ref) + PARdrU/(1.0-ref_dir)) + (PARdrD/(1.0-ref_dir) - 0.5 * swdircan(k_can)) &
                         +(PARdfD/(1.0-ref) - 0.5*swdifcan(k_can))) 
  end do

! calculate amount of upward light at canopy top coming from surface reflection (PARdrU and PARdfU with iLAI=0)
  PARdirref_TOC = PARdir_TOC * (1.0-ref_dir) * exp(-kdr * LAI) * alb *  exp(-kdf * (LAI-0)) ! Total dir upward at canopy top
  PARdifref_TOC = PARdif_TOC * (1.0-ref)     * exp(-kdf * LAI) * alb *  exp(-kdf * (LAI-0)) ! Total dif upward at canopy top
  !calculate effective albedos for direct, diffuse and total SW radiation assuming PAR and sw albedos are identical
  effalb_dir =  1-(((PARdir_TOC * (1.0-ref_dir))- PARdirref_TOC) / PARdir_TOC)
  effalb_dif =  1-(((PARdif_TOC * (1.0-ref))    - PARdifref_TOC) / PARdif_TOC)
  effalb_sw  =  1-(( ((PARdir_TOC*(1.0-ref_dir))-PARdirref_TOC) + ((PARdif_TOC*(1.0-ref))-PARdifref_TOC)) &
                /(PARdir_TOC + PARdif_TOC))
   
return
end subroutine ! canopyrad

subroutine f_Ags(CO2air,qtair,dens,tairk,pair,t_skin,          & ! in
                 phi_tot,Hleaf,                                & ! in
                 lrelaxgc,gc_old_set,kgc,gleaf_old,rk3coef,    & ! in
                 lrelaxci,ci_old_set,kci,ci_old,               & ! in
                 gleaf,Fleaf,ci,                               & ! out
                 fstr,Am,Rdark,alphac,co2abs,CO2comp,Ds,D0,fmin) ! additional out for 1leaf upscaling 

      implicit none
      real, intent(in) ::  CO2air   ! CO2 air concentration [ppb]
      real, intent(in) ::  qtair    ! air specific humidity [kg/kg]
      real, intent(in) ::  pair     ! air pressure          [Pa]
      real, intent(in) ::  dens     ! air density           [kg/m3]
      real, intent(in) ::  tairk    ! air temperature (K)
      real, intent(in) ::  t_skin   ! surface or leaf skin temperature (K)
      real, intent(in) ::  phi_tot  ! Total soil water content [-]
      real, intent(in) ::  Hleaf    ! absorbed PAR [W/m2]
      logical, intent(in) ::  lrelaxgc ! if true, lag in plant stomatal response
      logical, intent(in) ::  gc_old_set !false at first timestep, true at any  other
      real, intent(in) ::  kgc      ! Standard stomatal response rate
      real, intent(in) ::  gleaf_old ! gleaf at previous timestep
      real, intent(in) ::  rk3coef    ! runge kutta step
      logical, intent(in) ::  lrelaxci ! if true, lag in plant internal carbon response
      logical, intent(in) ::  ci_old_set !false at first timestep, true at any  other
      real, intent(in) ::  kci           ! Standard internal co2 concentration response rate
      real, intent(in) ::  ci_old        ! ci at previous timestep
      
      
      real, intent (out) :: gleaf   ! leaf stomatal conductance for carbon(m/s)
      real, intent (out) :: Fleaf    
      real, intent (out) :: ci     
      
      real, intent (out) :: fstr
      real, intent (out) :: Am
      real, intent (out) :: Rdark
      real, intent (out) :: alphac
      real, intent (out) :: co2abs
      real, intent (out) :: CO2comp
      real, intent (out) :: Ds
      real, intent (out) :: D0
      real, intent (out) :: fmin

      real     :: CO2ags, gm, fmin0, esatsurf, cfrac !Variables for AGS
      real     :: Ammax, betaw!Variables for AGS
      real     :: Agl,gleaf_inf
      ! variables below ma not be necessaruly defined when implemented properly
      real     :: e! needed here as well
      !this line is done in do_lsm, but we put it here because it will change per vert level
      e    = qtair * pair / 0.622

      CO2ags  = CO2air/1000.0  !From ppb (usual DALES standard) to ppm

      ! Calculate surface resistances using the plant physiological (A-gs) model
      ! Calculate the CO2 compensation concentration
      CO2comp = dens * CO2comp298 * Q10CO2 ** (0.1 * ( tairk - 298.0 ) )
      !CO2comp = dens * CO2comp298 * Q10CO2 ** (0.1 * ( t_skin - 298.0 ) ) !!proposal pending

      ! Calculate the mesophyll conductance
      gm       = gm298 * Q10gm ** (0.1 * ( tairk - 298.0) ) / ( (1. + exp(0.3 * ( T1gm - tairk ))) * (1. + exp(0.3 * (tairk- T2gm))))
      gm       = gm / 1000   ! conversion from mm s-1 to m s-1

      ! calculate CO2 concentration inside the leaf (ci)
      fmin0    = gmin/nuco2q - (1.0/9.0) * gm
      fmin     = (-fmin0 + ( fmin0 ** 2.0 + 4 * gmin/nuco2q * gm ) ** (0.5)) / (2. * gm)

      esatsurf = 0.611e3 * exp(17.2694 * (t_skin - 273.16) / (t_skin - 35.86))
      Ds       = (esatsurf - e) / 1000.0 ! In kPa
      D0       = (f0 - fmin) / ad

      cfrac    = f0 * (1.0 - Ds/D0) + fmin * (Ds/D0)
      co2abs   = CO2ags * (MW_CO2/MW_Air) * dens

      ci_inf   = cfrac * (co2abs - CO2comp) + CO2comp
      if (lrelaxci .and. ci_old_set) then
        ci            = ci_old + min(kci*rk3coef, 1.0) * (ci_inf - ci_old)
      else
        ci            = ci_inf
      endif

      ! Calculate maximal gross primary production in high light conditions (Ag)
      Ammax    = Ammax298 * Q10am ** ( 0.1 * ( tairk - 298.0) ) / ( (1.0 + exp(0.3 * ( T1Am - tairk ))) * (1. + exp(0.3 * ( tairk - T2Am))) )

      ! Calculate the effect of soil moisture stress on gross assimilation rate
      betaw    = max(1.0e-3,min(1.0,(phi_tot-phiwp)/(phifc-phiwp)))

      ! Calculate stress function
      fstr     = betaw

      ! Calculate gross assimilation rate (Am)
      Am       = Ammax * (1 - exp( -(gm * (ci - CO2comp) / Ammax) ) )

      Rdark    = (1.0/9) * Am

      ! Calculate the light use efficiency
      alphac   = alpha0 * (co2abs  - CO2comp) / (co2abs + 2 * CO2comp)

      Agl    = fstr * (Am + Rdark) * (1 - exp(-alphac*Hleaf/(Am + Rdark)))
      gleaf_inf  = gmin/nuco2q +  Agl/(co2abs-ci)
      !gleaf  = gmin/nuco2q +  max(Agl/(co2abs-ci),0.0)  ! put a floor on gleaf to avoid negative values  XPB
      
      Fleaf  = -(Agl - Rdark) ! we flip sign here to be consistent with An in old DALES 

      if (lrelaxgc .and. gc_old_set) then
          gleaf       = gleaf_old + min(kgc*rk3coef, 1.0) * (gleaf_inf - gleaf_old)
        else
          gleaf = gleaf_inf
      endif 
   return
end subroutine !Ags

end module modsurfdata
