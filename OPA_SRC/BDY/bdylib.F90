MODULE bdylib
   !!======================================================================
   !!                       ***  MODULE  bdylib  ***
   !! Unstructured Open Boundary Cond. :  Library module of generic boundary algorithms.
   !!======================================================================
   !! History :  3.6  !  2013     (D. Storkey) new module
   !!----------------------------------------------------------------------
#if defined key_bdy 
   !!----------------------------------------------------------------------
   !!   'key_bdy' :                    Unstructured Open Boundary Condition
   !!----------------------------------------------------------------------
   !!   bdy_orlanski_2d
   !!   bdy_orlanski_3d
   !!----------------------------------------------------------------------
   USE timing          ! Timing
   USE oce             ! ocean dynamics and tracers 
  USE dom_oce         ! ocean space and time domain
   USE bdy_oce         ! ocean open boundary conditions
  USE phycst          ! physical constants
  USE lbclnk          ! ocean lateral boundary conditions (or mpp link)
   USE in_out_manager  !

 
 
   IMPLICIT NONE
   PRIVATE

   PUBLIC   bdy_orlanski_2d     ! routine called in bdytra.f90
   PUBLIC   bdy_orlanski_3d     ! routine called in bdytra.f90
   PUBLIC   bdy_adv_frs_mod ! routine called in bdytra.f90
   PUBLIC   bdy_adv ! routine called in bdytra.f90

   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.3 , NEMO Consortium (2010)
   !! $Id: bdylib.F90 5215 2015-04-15 16:11:56Z nicolasmartin $ 
   !! Software governed by the CeCILL licence (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE bdy_orlanski_2d( idx, igrd, phib, phia, phi_ext, ll_npo )
      !!----------------------------------------------------------------------
      !!                 ***  SUBROUTINE bdy_orlanski_2d  ***
      !!             
      !!              - Apply Orlanski radiation condition adaptively to 2D fields:
      !!                  - radiation plus weak nudging at outflow points
      !!                  - no radiation and strong nudging at inflow points
      !! 
      !!
      !! References:  Marchesiello, McWilliams and Shchepetkin, Ocean Modelling vol. 3 (2001)    
      !!----------------------------------------------------------------------
      TYPE(OBC_INDEX),            INTENT(in)     ::   idx      ! BDY indices
      INTEGER,                    INTENT(in)     ::   igrd     ! grid index
      REAL(wp), DIMENSION(:,:),   INTENT(in)     ::   phib     ! model before 2D field
      REAL(wp), DIMENSION(:,:),   INTENT(inout)  ::   phia     ! model after 2D field (to be updated)
      REAL(wp), DIMENSION(:),     INTENT(in)     ::   phi_ext  ! external forcing data
      LOGICAL,                    INTENT(in)     ::   ll_npo   ! switch for NPO version

      INTEGER  ::   jb                                     ! dummy loop indices
      INTEGER  ::   ii, ij, iibm1, iibm2, ijbm1, ijbm2     ! 2D addresses
      INTEGER  ::   iijm1, iijp1, ijjm1, ijjp1             ! 2D addresses
      INTEGER  ::   iibm1jp1, iibm1jm1, ijbm1jp1, ijbm1jm1 ! 2D addresses
      INTEGER  ::   ii_offset, ij_offset                   ! offsets for mask indices
      INTEGER  ::   flagu, flagv                           ! short cuts
      REAL(wp) ::   zmask_x, zmask_y1, zmask_y2
      REAL(wp) ::   zex1, zex2, zey, zey1, zey2
      REAL(wp) ::   zdt, zdx, zdy, znor2, zrx, zry         ! intermediate calculations
      REAL(wp) ::   zout, zwgt, zdy_centred
      REAL(wp) ::   zdy_1, zdy_2, zsign_ups
      REAL(wp), PARAMETER :: zepsilon = 1.e-30                 ! local small value
      REAL(wp), POINTER, DIMENSION(:,:)          :: pmask      ! land/sea mask for field
      REAL(wp), POINTER, DIMENSION(:,:)          :: pmask_xdif ! land/sea mask for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pmask_ydif ! land/sea mask for y-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_xdif    ! scale factors for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_ydif    ! scale factors for y-derivatives
      !!----------------------------------------------------------------------

      IF( nn_timing == 1 ) CALL timing_start('bdy_orlanski_2d')

      ! ----------------------------------!
      ! Orlanski boundary conditions     :!
      ! ----------------------------------! 
     
      SELECT CASE(igrd)
         CASE(1)
            pmask => tmask(:,:,1)
            pmask_xdif => umask(:,:,1)
            pmask_ydif => vmask(:,:,1)
            pe_xdif => e1u(:,:)
            pe_ydif => e2v(:,:)
            ii_offset = 0
            ij_offset = 0
         CASE(2)
            pmask => umask(:,:,1)
            pmask_xdif => tmask(:,:,1)
            pmask_ydif => fmask(:,:,1)
            pe_xdif => e1t(:,:)
            pe_ydif => e2f(:,:)
            ii_offset = 1
            ij_offset = 0
         CASE(3)
            pmask => vmask(:,:,1)
            pmask_xdif => fmask(:,:,1)
            pmask_ydif => tmask(:,:,1)
            pe_xdif => e1f(:,:)
            pe_ydif => e2t(:,:)
            ii_offset = 0
            ij_offset = 1
         CASE DEFAULT ;   CALL ctl_stop( 'unrecognised value for igrd in bdy_orlanksi_2d' )
      END SELECT
      !
      DO jb = 1, idx%nblenrim(igrd)
         ii  = idx%nbi(jb,igrd)
         ij  = idx%nbj(jb,igrd) 
         flagu = int( idx%flagu(jb,igrd) )
         flagv = int( idx%flagv(jb,igrd) )
         !
         ! Calculate positions of b-1 and b-2 points for this rim point
         ! also (b-1,j-1) and (b-1,j+1) points
         iibm1 = ii + flagu ; iibm2 = ii + 2*flagu 
         ijbm1 = ij + flagv ; ijbm2 = ij + 2*flagv
          !
         iijm1 = ii - abs(flagv) ; iijp1 = ii + abs(flagv) 
         ijjm1 = ij - abs(flagu) ; ijjp1 = ij + abs(flagu)
         !
         iibm1jm1 = ii + flagu - abs(flagv) ; iibm1jp1 = ii + flagu + abs(flagv) 
         ijbm1jm1 = ij + flagv - abs(flagu) ; ijbm1jp1 = ij + flagv + abs(flagu) 
         !
         ! Calculate scale factors for calculation of spatial derivatives.        
         zex1 = ( abs(iibm1-iibm2) * pe_xdif(iibm1+ii_offset,ijbm1          )         &
        &       + abs(ijbm1-ijbm2) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
         zex2 = ( abs(iibm1-iibm2) * pe_xdif(iibm2+ii_offset,ijbm2          )         &
        &       + abs(ijbm1-ijbm2) * pe_ydif(iibm2          ,ijbm2+ij_offset) ) 
         zey1 = ( (iibm1-iibm1jm1) * pe_xdif(iibm1jm1+ii_offset,ijbm1jm1          )  & 
        &      +  (ijbm1-ijbm1jm1) * pe_ydif(iibm1jm1          ,ijbm1jm1+ij_offset) ) 
         zey2 = ( (iibm1jp1-iibm1) * pe_xdif(iibm1+ii_offset,ijbm1)                  &
        &      +  (ijbm1jp1-ijbm1) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
         ! make sure scale factors are nonzero
         if( zey1 .lt. rsmall ) zey1 = zey2
         if( zey2 .lt. rsmall ) zey2 = zey1
         zex1 = max(zex1,rsmall); zex2 = max(zex2,rsmall)
         zey1 = max(zey1,rsmall); zey2 = max(zey2,rsmall); 
         !
         ! Calculate masks for calculation of spatial derivatives.        
         zmask_x = ( abs(iibm1-iibm2) * pmask_xdif(iibm2+ii_offset,ijbm2          )         &
        &          + abs(ijbm1-ijbm2) * pmask_ydif(iibm2          ,ijbm2+ij_offset) ) 
         zmask_y1 = ( (iibm1-iibm1jm1) * pmask_xdif(iibm1jm1+ii_offset,ijbm1jm1          )  & 
        &          +  (ijbm1-ijbm1jm1) * pmask_ydif(iibm1jm1          ,ijbm1jm1+ij_offset) ) 
         zmask_y2 = ( (iibm1jp1-iibm1) * pmask_xdif(iibm1+ii_offset,ijbm1)                  &
        &          +  (ijbm1jp1-ijbm1) * pmask_ydif(iibm1          ,ijbm1+ij_offset) ) 

         ! Calculation of terms required for both versions of the scheme. 
         ! Mask derivatives to ensure correct land boundary conditions for each variable.
         ! Centred derivative is calculated as average of "left" and "right" derivatives for 
         ! this reason. 
         ! Note no rdt factor in expression for zdt because it cancels in the expressions for 
         ! zrx and zry.
         zdt = phia(iibm1,ijbm1) - phib(iibm1,ijbm1)
         zdx = ( ( phia(iibm1,ijbm1) - phia(iibm2,ijbm2) ) / zex2 ) * zmask_x 
         zdy_1 = ( ( phib(iibm1   ,ijbm1   ) - phib(iibm1jm1,ijbm1jm1) ) / zey1 ) * zmask_y1    
         zdy_2 = ( ( phib(iibm1jp1,ijbm1jp1) - phib(iibm1   ,ijbm1)    ) / zey2 ) * zmask_y2 
         zdy_centred = 0.5 * ( zdy_1 + zdy_2 )
!!$         zdy_centred = phib(iibm1jp1,ijbm1jp1) - phib(iibm1jm1,ijbm1jm1)
         ! upstream differencing for tangential derivatives
         zsign_ups = sign( 1., zdt * zdy_centred )
         zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
         zdy = zsign_ups * zdy_1 + (1. - zsign_ups) * zdy_2
         znor2 = zdx * zdx + zdy * zdy
         znor2 = max(znor2,zepsilon)
         !
         zrx = zdt * zdx / ( zex1 * znor2 ) 
!!$         zrx = min(zrx,2.0_wp)
         zout = sign( 1., zrx )
         zout = 0.5*( zout + abs(zout) )
         zwgt = 2.*rdt*( (1.-zout) * idx%nbd(jb,igrd) + zout * idx%nbdout(jb,igrd) )
         ! only apply radiation on outflow points 
         if( ll_npo ) then     !! NPO version !!
            phia(ii,ij) = (1.-zout) * ( phib(ii,ij) + zwgt * ( phi_ext(jb) - phib(ii,ij) ) )        &
           &            + zout      * ( phib(ii,ij) + zrx*phia(iibm1,ijbm1)                         &
           &                            + zwgt * ( phi_ext(jb) - phib(ii,ij) ) ) / ( 1. + zrx ) 
         else                  !! full oblique radiation !!
            zsign_ups = sign( 1., zdt * zdy )
            zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
            zey = zsign_ups * zey1 + (1.-zsign_ups) * zey2 
            zry = zdt * zdy / ( zey * znor2 ) 
            phia(ii,ij) = (1.-zout) * ( phib(ii,ij) + zwgt * ( phi_ext(jb) - phib(ii,ij) ) )        &
           &            + zout      * ( phib(ii,ij) + zrx*phia(iibm1,ijbm1)                         &
           &                    - zsign_ups      * zry * ( phib(ii   ,ij   ) - phib(iijm1,ijjm1 ) ) &
           &                    - (1.-zsign_ups) * zry * ( phib(iijp1,ijjp1) - phib(ii   ,ij    ) ) &
           &                    + zwgt * ( phi_ext(jb) - phib(ii,ij) ) ) / ( 1. + zrx ) 
         end if
         phia(ii,ij) = phia(ii,ij) * pmask(ii,ij)
      END DO
      !
      IF( nn_timing == 1 ) CALL timing_stop('bdy_orlanski_2d')

   END SUBROUTINE bdy_orlanski_2d


   SUBROUTINE bdy_orlanski_3d( idx, igrd, phib, phia, phi_ext, ll_npo )
      !!----------------------------------------------------------------------
      !!                 ***  SUBROUTINE bdy_orlanski_3d  ***
      !!             
      !!              - Apply Orlanski radiation condition adaptively to 3D fields:
      !!                  - radiation plus weak nudging at outflow points
      !!                  - no radiation and strong nudging at inflow points
      !! 
      !!
      !! References:  Marchesiello, McWilliams and Shchepetkin, Ocean Modelling vol. 3 (2001)    
      !!----------------------------------------------------------------------
      TYPE(OBC_INDEX),            INTENT(in)     ::   idx      ! BDY indices
      INTEGER,                    INTENT(in)     ::   igrd     ! grid index
      REAL(wp), DIMENSION(:,:,:), INTENT(in)     ::   phib     ! model before 3D field
      REAL(wp), DIMENSION(:,:,:), INTENT(inout)  ::   phia     ! model after 3D field (to be updated)
      REAL(wp), DIMENSION(:,:),   INTENT(in)     ::   phi_ext  ! external forcing data
      LOGICAL,                    INTENT(in)     ::   ll_npo   ! switch for NPO version

      INTEGER  ::   jb, jk                                 ! dummy loop indices
      INTEGER  ::   ii, ij, iibm1, iibm2, ijbm1, ijbm2     ! 2D addresses
      INTEGER  ::   iijm1, iijp1, ijjm1, ijjp1             ! 2D addresses
      INTEGER  ::   iibm1jp1, iibm1jm1, ijbm1jp1, ijbm1jm1 ! 2D addresses
      INTEGER  ::   ii_offset, ij_offset                   ! offsets for mask indices
      INTEGER  ::   flagu, flagv                           ! short cuts
      REAL(wp) ::   zmask_x, zmask_y1, zmask_y2
      REAL(wp) ::   zex1, zex2, zey, zey1, zey2
      REAL(wp) ::   zdt, zdx, zdy, znor2, zrx, zry         ! intermediate calculations
      REAL(wp) ::   zout, zwgt, zdy_centred
      REAL(wp) ::   zdy_1, zdy_2,  zsign_ups
      REAL(wp), PARAMETER :: zepsilon = 1.e-30                 ! local small value
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask      ! land/sea mask for field
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask_xdif ! land/sea mask for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask_ydif ! land/sea mask for y-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_xdif    ! scale factors for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_ydif    ! scale factors for y-derivatives
      !!----------------------------------------------------------------------

      IF( nn_timing == 1 ) CALL timing_start('bdy_orlanski_3d')

      ! ----------------------------------!
      ! Orlanski boundary conditions     :!
      ! ----------------------------------! 
     
      SELECT CASE(igrd)
         CASE(1)
            pmask => tmask(:,:,:)
            pmask_xdif => umask(:,:,:)
            pmask_ydif => vmask(:,:,:)
            pe_xdif => e1u(:,:)
            pe_ydif => e2v(:,:)
            ii_offset = 0
            ij_offset = 0
         CASE(2)
            pmask => umask(:,:,:)
            pmask_xdif => tmask(:,:,:)
            pmask_ydif => fmask(:,:,:)
            pe_xdif => e1t(:,:)
            pe_ydif => e2f(:,:)
            ii_offset = 1
            ij_offset = 0
         CASE(3)
            pmask => vmask(:,:,:)
            pmask_xdif => fmask(:,:,:)
            pmask_ydif => tmask(:,:,:)
            pe_xdif => e1f(:,:)
            pe_ydif => e2t(:,:)
            ii_offset = 0
            ij_offset = 1
         CASE DEFAULT ;   CALL ctl_stop( 'unrecognised value for igrd in bdy_orlanksi_2d' )
      END SELECT

      DO jk = 1, jpk
         !            
         DO jb = 1, idx%nblenrim(igrd)
            ii  = idx%nbi(jb,igrd)
            ij  = idx%nbj(jb,igrd) 
            flagu = int( idx%flagu(jb,igrd) )
            flagv = int( idx%flagv(jb,igrd) )
            !
            ! calculate positions of b-1 and b-2 points for this rim point
            ! also (b-1,j-1) and (b-1,j+1) points
            iibm1 = ii + flagu ; iibm2 = ii + 2*flagu 
            ijbm1 = ij + flagv ; ijbm2 = ij + 2*flagv
            !
            iijm1 = ii - abs(flagv) ; iijp1 = ii + abs(flagv) 
            ijjm1 = ij - abs(flagu) ; ijjp1 = ij + abs(flagu)
            !
            iibm1jm1 = ii + flagu - abs(flagv) ; iibm1jp1 = ii + flagu + abs(flagv) 
            ijbm1jm1 = ij + flagv - abs(flagu) ; ijbm1jp1 = ij + flagv + abs(flagu) 
            !
            ! Calculate scale factors for calculation of spatial derivatives.        
            zex1 = ( abs(iibm1-iibm2) * pe_xdif(iibm1+ii_offset,ijbm1          )         &
           &       + abs(ijbm1-ijbm2) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
            zex2 = ( abs(iibm1-iibm2) * pe_xdif(iibm2+ii_offset,ijbm2          )         &
           &       + abs(ijbm1-ijbm2) * pe_ydif(iibm2          ,ijbm2+ij_offset) ) 
            zey1 = ( (iibm1-iibm1jm1) * pe_xdif(iibm1jm1+ii_offset,ijbm1jm1          )  & 
           &      +  (ijbm1-ijbm1jm1) * pe_ydif(iibm1jm1          ,ijbm1jm1+ij_offset) ) 
            zey2 = ( (iibm1jp1-iibm1) * pe_xdif(iibm1+ii_offset,ijbm1)                  &
           &      +  (ijbm1jp1-ijbm1) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
            ! make sure scale factors are nonzero
            if( zey1 .lt. rsmall ) zey1 = zey2
            if( zey2 .lt. rsmall ) zey2 = zey1
            zex1 = max(zex1,rsmall); zex2 = max(zex2,rsmall); 
            zey1 = max(zey1,rsmall); zey2 = max(zey2,rsmall); 
            !
            ! Calculate masks for calculation of spatial derivatives.        
            zmask_x = ( abs(iibm1-iibm2) * pmask_xdif(iibm2+ii_offset,ijbm2          ,jk)          &
           &          + abs(ijbm1-ijbm2) * pmask_ydif(iibm2          ,ijbm2+ij_offset,jk) ) 
            zmask_y1 = ( (iibm1-iibm1jm1) * pmask_xdif(iibm1jm1+ii_offset,ijbm1jm1          ,jk)   & 
           &          +  (ijbm1-ijbm1jm1) * pmask_ydif(iibm1jm1          ,ijbm1jm1+ij_offset,jk) ) 
            zmask_y2 = ( (iibm1jp1-iibm1) * pmask_xdif(iibm1+ii_offset,ijbm1          ,jk)         &
           &          +  (ijbm1jp1-ijbm1) * pmask_ydif(iibm1          ,ijbm1+ij_offset,jk) ) 
            !
            ! Calculate normal (zrx) and tangential (zry) components of radiation velocities.
            ! Mask derivatives to ensure correct land boundary conditions for each variable.
            ! Centred derivative is calculated as average of "left" and "right" derivatives for 
            ! this reason. 
            zdt = phia(iibm1,ijbm1,jk) - phib(iibm1,ijbm1,jk)
            zdx = ( ( phia(iibm1,ijbm1,jk) - phia(iibm2,ijbm2,jk) ) / zex2 ) * zmask_x                  
            zdy_1 = ( ( phib(iibm1   ,ijbm1   ,jk) - phib(iibm1jm1,ijbm1jm1,jk) ) / zey1 ) * zmask_y1  
            zdy_2 = ( ( phib(iibm1jp1,ijbm1jp1,jk) - phib(iibm1   ,ijbm1   ,jk) ) / zey2 ) * zmask_y2      
            zdy_centred = 0.5 * ( zdy_1 + zdy_2 )
!!$            zdy_centred = phib(iibm1jp1,ijbm1jp1,jk) - phib(iibm1jm1,ijbm1jm1,jk)
            ! upstream differencing for tangential derivatives
            zsign_ups = sign( 1., zdt * zdy_centred )
            zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
            zdy = zsign_ups * zdy_1 + (1. - zsign_ups) * zdy_2
            znor2 = zdx * zdx + zdy * zdy
            znor2 = max(znor2,zepsilon)
            !
            ! update boundary value:
            zrx = zdt * zdx / ( zex1 * znor2 )
!!$            zrx = min(zrx,2.0_wp)
            zout = sign( 1., zrx )
            zout = 0.5*( zout + abs(zout) )
            zwgt = 2.*rdt*( (1.-zout) * idx%nbd(jb,igrd) + zout * idx%nbdout(jb,igrd) )
            ! only apply radiation on outflow points 
            if( ll_npo ) then     !! NPO version !!
               phia(ii,ij,jk) = (1.-zout) * ( phib(ii,ij,jk) + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) ) &
              &               + zout      * ( phib(ii,ij,jk) + zrx*phia(iibm1,ijbm1,jk)                     &
              &                            + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) ) / ( 1. + zrx ) 
            else                  !! full oblique radiation !!
               zsign_ups = sign( 1., zdt * zdy )
               zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
               zey = zsign_ups * zey1 + (1.-zsign_ups) * zey2 
               zry = zdt * zdy / ( zey * znor2 ) 
               phia(ii,ij,jk) = (1.-zout) * ( phib(ii,ij,jk) + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) )    &
              &               + zout      * ( phib(ii,ij,jk) + zrx*phia(iibm1,ijbm1,jk)                        &
              &                       - zsign_ups      * zry * ( phib(ii   ,ij   ,jk) - phib(iijm1,ijjm1,jk) ) &
              &                       - (1.-zsign_ups) * zry * ( phib(iijp1,ijjp1,jk) - phib(ii   ,ij   ,jk) ) &
              &                       + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) ) / ( 1. + zrx ) 
            end if
            phia(ii,ij,jk) = phia(ii,ij,jk) * pmask(ii,ij,jk)
         END DO
         !
      END DO

      IF( nn_timing == 1 ) CALL timing_stop('bdy_orlanski_3d')

   END SUBROUTINE bdy_orlanski_3d
   
   SUBROUTINE bdy_adv_frs_mod( idx, igrd, phib, phia, phi_ext ) !(ADDED AH 30.06.2017)
      !!----------------------------------------------------------------------
      !!                 ***  SUBROUTINE bdy_orlanski_3d_frs_mod  ***
      !!             
      !!              - Apply Orlanski radiation condition adaptively to 3D fields:
      !!                  - radiation plus weak nudging at outflow points
      !!                  - FRS conditions at inflow points
      !! 
      !!
      !! References:  Marchesiello, McWilliams and Shchepetkin, Ocean Modelling vol. 3 (2001)    
      !!----------------------------------------------------------------------
      TYPE(OBC_INDEX),            INTENT(in)     ::   idx      ! BDY indices
      INTEGER,                    INTENT(in)     ::   igrd     ! grid index
      REAL(wp), DIMENSION(:,:,:), INTENT(in)     ::   phib     ! model before 3D field
      REAL(wp), DIMENSION(:,:,:), INTENT(inout)  ::   phia     ! model after 3D field (to be updated)
      REAL(wp), DIMENSION(:,:),   INTENT(in)     ::   phi_ext  ! external forcing data

      INTEGER  ::   jb, jk,ib,bcoord                              ! dummy loop indices
      INTEGER  ::   ii, ij, iibm1, iibm2, ijbm1, ijbm2     ! 2D addresses
      INTEGER  ::   iijm1, iijp1, ijjm1, ijjp1             ! 2D addresses
      INTEGER  ::   iibm1jp1, iibm1jm1, ijbm1jp1, ijbm1jm1 ! 2D addresses
      INTEGER  ::   ii_offset, ij_offset                   ! offsets for mask indices
      INTEGER  ::   flagu, flagv                           ! short cuts
      REAL(wp) ::   zmask_x, zmask_y1, zmask_y2
      REAL(wp) ::   zex1, zex2, zey, zey1, zey2
      REAL(wp) ::   zdt, zdx, zdy, znor2, zrx, zry       ! intermediate calculations
      REAL(wp) ::   zout, zwgt, zdy_centred, zwgtFRS
      REAL(wp) ::   zdy_1, zdy_2,  zsign_ups
      REAL(wp), PARAMETER :: zepsilon = 1.e-30                 ! local small value
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask      ! land/sea mask for field
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask_xdif ! land/sea mask for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:,:)        :: pmask_ydif ! land/sea mask for y-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_xdif    ! scale factors for x-derivatives
      REAL(wp), POINTER, DIMENSION(:,:)          :: pe_ydif    ! scale factors for y-derivatives
      !!----------------------------------------------------------------------

      IF( nn_timing == 1 ) CALL timing_start('bdy_orlanski_3d')

      ! ----------------------------------!
      ! Orlanski boundary conditions     :!
      ! ----------------------------------! 
     
      SELECT CASE(igrd)
         CASE(1)
            pmask => tmask(:,:,:)
            pmask_xdif => umask(:,:,:)
            pmask_ydif => vmask(:,:,:)
            pe_xdif => e1u(:,:)
            pe_ydif => e2v(:,:)
            ii_offset = 0
            ij_offset = 0
         CASE(2)
            pmask => umask(:,:,:)
            pmask_xdif => tmask(:,:,:)
            pmask_ydif => fmask(:,:,:)
            pe_xdif => e1t(:,:)
            pe_ydif => e2f(:,:)
            ii_offset = 1
            ij_offset = 0
         CASE(3)
            pmask => vmask(:,:,:)
            pmask_xdif => fmask(:,:,:)
            pmask_ydif => tmask(:,:,:)
            pe_xdif => e1f(:,:)
            pe_ydif => e2t(:,:)
            ii_offset = 0
            ij_offset = 1
         CASE DEFAULT ;   CALL ctl_stop( 'unrecognised value for igrd in bdy_orlanksi_2d' )
      END SELECT

      DO jk = 1, jpk
         !            
         DO jb = 1, idx%nblenrim(igrd)
            ii  = idx%nbi(jb,igrd)
            ij  = idx%nbj(jb,igrd) 
            flagu = int( idx%flagu(jb,igrd) )
            flagv = int( idx%flagv(jb,igrd) )
            !
            ! calculate positions of b-1 and b-2 points for this rim point
            ! also (b-1,j-1) and (b-1,j+1) points
            iibm1 = ii + flagu ; iibm2 = ii + 2*flagu 
            ijbm1 = ij + flagv ; ijbm2 = ij + 2*flagv
            !
            iijm1 = ii - abs(flagv) ; iijp1 = ii + abs(flagv) 
            ijjm1 = ij - abs(flagu) ; ijjp1 = ij + abs(flagu)
            !
            iibm1jm1 = ii + flagu - abs(flagv) ; iibm1jp1 = ii + flagu + abs(flagv) 
            ijbm1jm1 = ij + flagv - abs(flagu) ; ijbm1jp1 = ij + flagv + abs(flagu) 
            !
            ! Calculate scale factors for calculation of spatial derivatives.        
            zex1 = ( abs(iibm1-iibm2) * pe_xdif(iibm1+ii_offset,ijbm1          )         &
           &       + abs(ijbm1-ijbm2) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
            zex2 = ( abs(iibm1-iibm2) * pe_xdif(iibm2+ii_offset,ijbm2          )         &
           &       + abs(ijbm1-ijbm2) * pe_ydif(iibm2          ,ijbm2+ij_offset) ) 
            zey1 = ( (iibm1-iibm1jm1) * pe_xdif(iibm1jm1+ii_offset,ijbm1jm1          )  & 
           &      +  (ijbm1-ijbm1jm1) * pe_ydif(iibm1jm1          ,ijbm1jm1+ij_offset) ) 
            zey2 = ( (iibm1jp1-iibm1) * pe_xdif(iibm1+ii_offset,ijbm1)                  &
           &      +  (ijbm1jp1-ijbm1) * pe_ydif(iibm1          ,ijbm1+ij_offset) ) 
            ! make sure scale factors are nonzero
            if( zey1 .lt. rsmall ) zey1 = zey2
            if( zey2 .lt. rsmall ) zey2 = zey1
            zex1 = max(zex1,rsmall); zex2 = max(zex2,rsmall); 
            zey1 = max(zey1,rsmall); zey2 = max(zey2,rsmall); 
            !
            ! Calculate masks for calculation of spatial derivatives.        
            zmask_x = ( abs(iibm1-iibm2) * pmask_xdif(iibm2+ii_offset,ijbm2          ,jk)          &
           &          + abs(ijbm1-ijbm2) * pmask_ydif(iibm2          ,ijbm2+ij_offset,jk) ) 
            zmask_y1 = ( (iibm1-iibm1jm1) * pmask_xdif(iibm1jm1+ii_offset,ijbm1jm1          ,jk)   & 
           &          +  (ijbm1-ijbm1jm1) * pmask_ydif(iibm1jm1          ,ijbm1jm1+ij_offset,jk) ) 
            zmask_y2 = ( (iibm1jp1-iibm1) * pmask_xdif(iibm1+ii_offset,ijbm1          ,jk)         &
           &          +  (ijbm1jp1-ijbm1) * pmask_ydif(iibm1          ,ijbm1+ij_offset,jk) ) 
            !
            ! Calculate normal (zrx) and tangential (zry) components of radiation velocities.
            ! Mask derivatives to ensure correct land boundary conditions for each variable.
            ! Centred derivative is calculated as average of "left" and "right" derivatives for 
            ! this reason. 
            zdt = phia(iibm1,ijbm1,jk) - phib(iibm1,ijbm1,jk)
            zdx = ( ( phia(iibm1,ijbm1,jk) - phia(iibm2,ijbm2,jk) ) / zex2 ) * zmask_x                  
            zdy_1 = ( ( phib(iibm1   ,ijbm1   ,jk) - phib(iibm1jm1,ijbm1jm1,jk) ) / zey1 ) * zmask_y1  
            zdy_2 = ( ( phib(iibm1jp1,ijbm1jp1,jk) - phib(iibm1   ,ijbm1   ,jk) ) / zey2 ) * zmask_y2      
            zdy_centred = 0.5 * ( zdy_1 + zdy_2 )
!!$            zdy_centred = phib(iibm1jp1,ijbm1jp1,jk) - phib(iibm1jm1,ijbm1jm1,jk)
            ! upstream differencing for tangential derivatives
            zsign_ups = sign( 1., zdt * zdy_centred )
            zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
            zdy = zsign_ups * zdy_1 + (1. - zsign_ups) * zdy_2
            znor2 = zdx * zdx + zdy * zdy
            znor2 = max(znor2,zepsilon)
            !
            ! update boundary value:
            zrx = zdt * zdx / ( zex1 * znor2 )
			IF (zrx>0) then 
			zrx=zrx+(rdt/zex2)*ub(ii,ij,jk) ! u should have same dimension (i.e. be dimensionless) as zrx in order to be added 
			endif
!!$            zrx = min(zrx,2.0_wp)
            zout = sign( 1., zrx )
            zout = 0.5*( zout + abs(zout) )
            zwgt = 2.*rdt*( (1.-zout) * idx%nbd(jb,igrd) + zout * idx%nbdout(jb,igrd) )
            ! only apply radiation on outflow points 
			if (zout>0) then
                !! NPO version !!
               phia(ii,ij,jk) = ( phib(ii,ij,jk) + zrx*phia(iibm1,ijbm1,jk) + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) ) / ( 1. + zrx ) 
			   else
		DO ib = 0, 9
			bcoord=jb+ib*idx%nblenrim(igrd)
		    ii = idx%nbi(bcoord,igrd)
            ij = idx%nbj(bcoord,igrd)
            zwgt = idx%nbw(bcoord,igrd)
            phia(ii,ij,jk) = ( phia(ii,ij,jk) + zwgt * ( phi_ext(bcoord,jk) - phia(ii,ij,jk) ) ) * tmask(ii,ij,jk)   
         END DO
		endif
            phia(ii,ij,jk) = phia(ii,ij,jk) * pmask(ii,ij,jk)
         END DO
         !
      END DO

      IF( nn_timing == 1 ) CALL timing_stop('bdy_orlanski_3d')

   END SUBROUTINE bdy_adv_frs_mod
   
      SUBROUTINE bdy_adv( idx, igrd, phib, phia, phi_ext) !Added AH 03.07.2017 (Modifed 25.07)
      !!----------------------------------------------------------------------
      !!                 ***  SUBROUTINE bdy_adv  ***
      !!             
      !!              - Apply Advection scheme 
	  !!			  - Could(should?) be augmented with FRS inflow ll_frs=.true. and
	  !!		phase speed C_T from Orlanski scheme 
      !! 
      !!
      !! References:  Palma, Matano, J.Geophys.Res. vol. 105 (2000)    
      !!----------------------------------------------------------------------
      TYPE(OBC_INDEX),            INTENT(in)     ::   idx      ! BDY indices
      INTEGER,                    INTENT(in)     ::   igrd     ! grid index
      REAL(wp), DIMENSION(:,:,:), INTENT(in)     ::   phib     ! model before 3D field
      REAL(wp), DIMENSION(:,:,:), INTENT(inout)  ::   phia     ! model after 3D field (to be updated)
      REAL(wp), DIMENSION(:,:),   INTENT(in)     ::   phi_ext  ! external forcing data

      INTEGER  ::   jb, jk,ib                                 ! dummy loop indices
      INTEGER  ::   ii, ij, iibm1, iibm2, ijbm1, ijbm2     ! 2D addresses
      INTEGER  ::   iijm1, iijp1, ijjm1, ijjp1             ! 2D addresses
      INTEGER  ::   iibm1jp1, iibm1jm1, ijbm1jp1, ijbm1jm1 ! 2D addresses
      INTEGER  ::   flagu, flagv                           ! short cuts
      REAL(wp) ::   zmask_x, zmask_y1, zmask_y2
      REAL(wp) ::   zex1, zex2, zey, zey1, zey2
      REAL(wp) ::   zdt, zdx, zdy, znor2, zrx, zry,zrx1        ! intermediate calculations
      REAL(wp) ::   zout, zwgt, zdy_centred, zwgtFRS
      REAL(wp) ::   zdy_1, zdy_2,  zsign_ups
      REAL(wp), PARAMETER :: zepsilon = 1.e-30                 ! local small value
      !!----------------------------------------------------------------------

      IF( nn_timing == 1 ) CALL timing_start('bdy_orlanski_3d')

      DO jk = 1, jpk
         !            
         DO jb = 1, idx%nblenrim(igrd)
            ii  = idx%nbi(jb,igrd)
            ij  = idx%nbj(jb,igrd) 
            flagu = int( idx%flagu(jb,igrd) )
            flagv = int( idx%flagv(jb,igrd) )
            !
            ! calculate positions of b-1 and b-2 points for this rim point
            ! also (b-1,j-1) and (b-1,j+1) points
            iibm1 = ii + flagu ; iibm2 = ii + 2*flagu 
            ijbm1 = ij + flagv ; ijbm2 = ij + 2*flagv
            !
            iijm1 = ii - abs(flagv) ; iijp1 = ii + abs(flagv) 
            ijjm1 = ij - abs(flagu) ; ijjp1 = ij + abs(flagu)
            !
            iibm1jm1 = ii + flagu - abs(flagv) ; iibm1jp1 = ii + flagu + abs(flagv) 
            ijbm1jm1 = ij + flagv - abs(flagu) ; ijbm1jp1 = ij + flagv + abs(flagu) 
            !
            ! Calculate scale factors for calculation of spatial derivatives.        
            zex1 = ( abs(iibm1-iibm2) * e1u(iibm1,ijbm1)+abs(ijbm1-ijbm2) * e2v(iibm1,ijbm1) ) 
            zex2 = ( abs(iibm1-iibm2) * e1u(iibm2,ijbm2) + abs(ijbm1-ijbm2) * e2v(iibm2,ijbm2) ) 
            zey1 = ( (iibm1-iibm1jm1) * e1u(iibm1jm1,ijbm1jm1) +  (ijbm1-ijbm1jm1) * e2v(iibm1jm1,ijbm1jm1) ) 
            zey2 = ( (iibm1jp1-iibm1) * e1u(iibm1,ijbm1) +  (ijbm1jp1-ijbm1) * e2v(iibm1,ijbm1)) 
            ! make sure scale factors are nonzero
            if( zey1 .lt. rsmall ) zey1 = zey2
            if( zey2 .lt. rsmall ) zey2 = zey1
            zex1 = max(zex1,rsmall); zex2 = max(zex2,rsmall); 
            zey1 = max(zey1,rsmall); zey2 = max(zey2,rsmall); 
            !
            ! Calculate masks for calculation of spatial derivatives.        
            zmask_x = ( abs(iibm1-iibm2) * umask(iibm2,ijbm2,jk) + abs(ijbm1-ijbm2) * vmask(iibm2,ijbm2,jk) ) 
            zmask_y1 = ( (iibm1-iibm1jm1) * umask(iibm1jm1,ijbm1jm1,jk) +  (ijbm1-ijbm1jm1) * vmask(iibm1jm1,ijbm1jm1,jk) ) 
            zmask_y2 = ( (iibm1jp1-iibm1) * umask(iibm1,ijbm1,jk) + (ijbm1jp1-ijbm1) * vmask(iibm1,ijbm1,jk) ) 
            !
            ! Calculate normal (zrx) and tangential (zry) components of radiation velocities.
            ! Mask derivatives to ensure correct land boundary conditions for each variable.
            ! Centred derivative is calculated as average of "left" and "right" derivatives for 
            ! this reason. 
            zdt = phia(iibm1,ijbm1,jk) - phib(iibm1,ijbm1,jk)
            zdx = ( ( phia(iibm1,ijbm1,jk) - phia(iibm2,ijbm2,jk) ) / zex2 ) * zmask_x                  
            zdy_1 = ( ( phib(iibm1,ijbm1,jk) - phib(iibm1jm1,ijbm1jm1,jk) ) / zey1 ) * zmask_y1  
            zdy_2 = ( ( phib(iibm1jp1,ijbm1jp1,jk) - phib(iibm1,ijbm1,jk) ) / zey2 ) * zmask_y2      
            zdy_centred = 0.5 * ( zdy_1 + zdy_2 )
            ! upstream differencing for tangential derivatives
            zsign_ups = sign( 1., zdt * zdy_centred )
            zsign_ups = 0.5*( zsign_ups + abs(zsign_ups) )
            zdy = zsign_ups * zdy_1 + (1. - zsign_ups) * zdy_2
            znor2 = zdx * zdx + zdy * zdy
            znor2 = max(znor2,zepsilon)
            !
            ! update boundary value:
            zrx = zdt * zdx / ( zex1 * znor2 )
			zrx1=zrx
			IF (zrx1>0) then 
			zrx1=zrx1+(rdt/zex2)*ub(ii,ij,jk) ! u should have same dimension (i.e. be dimensionless) as zrx in order to be added 
			endif
!!$            zrx = min(zrx,2.0_wp)
            zout = sign( 1., zrx )
            zout = 0.5*( zout + abs(zout) )
            zwgt = 2.*rdt*( (1.-zout) * idx%nbd(jb,igrd) + zout * idx%nbdout(jb,igrd) )
			zwgtFRS=idx%nbw(jb,igrd)
            ! only apply radiation on outflow points 
			if (zout>0) then
                !! NPO version !!
               phia(ii,ij,jk) = ( phib(ii,ij,jk) + zrx1*phia(iibm1,ijbm1,jk) + zwgt * ( phi_ext(jb,jk) - phib(ii,ij,jk) ) ) / ( 1. + zrx1 ) 
			   else
		DO ib = 1, idx%nblen(igrd)
		    ii = idx%nbi(ib,igrd)
            ij = idx%nbj(ib,igrd)
            zwgt = idx%nbw(ib,igrd)
            phia(ii,ij,jk) = ( phia(ii,ij,jk) + zwgt * ( phi_ext(ib,jk) - phia(ii,ij,jk) ) ) * tmask(ii,ij,jk)   
         END DO
		endif
            phia(ii,ij,jk) = phia(ii,ij,jk) * tmask(ii,ij,jk)
         END DO
         !
      END DO
	  
   END SUBROUTINE bdy_adv
   

   

#else
   !!----------------------------------------------------------------------
   !!   Dummy module                   NO Unstruct Open Boundary Conditions
   !!----------------------------------------------------------------------
CONTAINS
   SUBROUTINE bdy_orlanski_2d( idx, igrd, phib, phia, phi_ext  )      ! Empty routine
      WRITE(*,*) 'bdy_orlanski_2d: You should not have seen this print! error?', kt
   END SUBROUTINE bdy_orlanski_2d
   SUBROUTINE bdy_orlanski_3d( idx, igrd, phib, phia, phi_ext  )      ! Empty routine
      WRITE(*,*) 'bdy_orlanski_3d: You should not have seen this print! error?', kt
   END SUBROUTINE bdy_orlanski_3d
#endif

   !!======================================================================
END MODULE bdylib
