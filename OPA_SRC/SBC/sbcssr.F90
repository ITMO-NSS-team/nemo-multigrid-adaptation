MODULE sbcssr
   !!======================================================================
   !!                       ***  MODULE  sbcssr  ***
   !! Surface module :  heat and fresh water fluxes a restoring term toward observed SST/SSS
   !!======================================================================
   !! History :  3.0  !  2006-06  (G. Madec)  Original code
   !!            3.2  !  2009-04  (B. Lemaire)  Introduce iom_put
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   sbc_ssr       : add to sbc a restoring term toward SST/SSS climatology
   !!   sbc_ssr_init  : initialisation of surface restoring
   !!----------------------------------------------------------------------
   USE oce            ! ocean dynamics and tracers
   USE dom_oce        ! ocean space and time domain
   USE sbc_oce        ! surface boundary condition
   USE phycst         ! physical constants
   USE sbcrnf         ! surface boundary condition : runoffs
   !
   USE fldread        ! read input fields
   USE iom            ! I/O manager
   USE in_out_manager ! I/O manager
   USE lib_mpp        ! distribued memory computing library
   USE lbclnk         ! ocean lateral boundary conditions (or mpp link)
   USE timing         ! Timing
   USE lib_fortran    ! Fortran utilities (allows no signed zero when 'key_nosignedzero' defined)  
   USE eosbn2         ! equation of state

# if defined key_lim3
   USE sbc_ice        ! surface boundary condition 
   USE ice
# endif
   IMPLICIT NONE
   PRIVATE

   PUBLIC   sbc_ssr        ! routine called in sbcmod
   PUBLIC   sbc_ssr_ice    ! routine called in sbcblk_clio
   PUBLIC   sbc_ssr_init   ! routine called in sbcmod

   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:) ::   erp   !: evaporation damping   [kg/m2/s]
   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:) ::   qrp   !: heat flux damping        [w/m2]
   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:) ::   qrp_ice   !: heat flux damping        [w/m2]
   REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:) ::   freez_temp   !

   !                                   !!* Namelist namsbc_ssr *
   INTEGER, PUBLIC ::   nn_sstr         ! SST/SSS restoring indicator
   INTEGER, PUBLIC ::   nn_ssir         ! SSI restoring indicator
   INTEGER, PUBLIC ::   nn_sssr         ! SST/SSS restoring indicator
   REAL(wp)        ::   rn_dqdt         ! restoring factor on SST and SSS
   
   REAL(wp)        ::   rn_dqdi_melt         ! restoring factor on SSI concentration melting
   REAL(wp)        ::   rn_dqdi_freez   ! restoring factor on SSI concentration freezing
   
   REAL(wp)        ::   rn_dqdi_thick_melt   ! restoring factor on SSI thickness melting
   REAL(wp)        ::   rn_dqdi_thick_freez   ! restoring factor on SSI thickness freezing
   
   
   REAL(wp)        ::   rn_deds         ! restoring factor on SST and SSS
   LOGICAL         ::   ln_sssr_bnd     ! flag to bound erp term 
   REAL(wp)        ::   rn_sssr_bnd     ! ABS(Max./Min.) value of erp term [mm/day]
   
   REAL(wp) :: ice_resto,ice_resto_conc,ice_resto_thic,ice_resto_mask

   REAL(wp) , ALLOCATABLE, DIMENSION(:) ::   buffer   ! Temporary buffer for exchange
   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_sst   ! structure of input SST (file informations, fields read)
   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_ssi   ! structure of input SSI (file informations, fields read)
   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_ssit  ! structure of input SSIT (file informations, fields read)
   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_ssit_error  ! structure of input SSIT error (file informations, fields read)

   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_sss   ! structure of input SSS (file informations, fields read)
   TYPE(FLD), ALLOCATABLE, DIMENSION(:) ::   sf_resto  ! structure of input resto mask (file informations, fields read)

   


   !! * Substitutions
#  include "domzgr_substitute.h90"
   !!----------------------------------------------------------------------
   !! NEMO/OPA 4.0 , NEMO Consortium (2011)
   !! $Id: sbcssr.F90 4990 2014-12-15 16:42:49Z timgraham $
   !! Software governed by the CeCILL licence     (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE sbc_ssr( kt )
      !!---------------------------------------------------------------------
      !!                     ***  ROUTINE sbc_ssr  ***
      !!
      !! ** Purpose :   Add to heat and/or freshwater fluxes a damping term
      !!                toward observed SST and/or SSS.
      !!
      !! ** Method  : - Read namelist namsbc_ssr
      !!              - Read observed SST and/or SSS
      !!              - at each nscb time step
      !!                   add a retroaction term on qns    (nn_sstr = 1)
      !!                   add a damping term on sfx        (nn_sssr = 1)
      !!                   add a damping term on emp        (nn_sssr = 2)
      !!---------------------------------------------------------------------
      INTEGER, INTENT(in   ) ::   kt   ! ocean time step
      !!
      INTEGER  ::   ji, jj   ! dummy loop indices
      REAL(wp) ::   zerp     ! local scalar for evaporation damping
      REAL(wp) ::   zqrp     ! local scalar for heat flux damping
      REAL(wp) ::   zsrp     ! local scalar for unit conversion of rn_deds factor
      REAL(wp) ::   zerp_bnd ! local scalar for unit conversion of rn_epr_max factor
      INTEGER  ::   ierror   ! return error code
      !!
      CHARACTER(len=100) ::  cn_dir          ! Root directory for location of ssr files
      TYPE(FLD_N) ::   sn_sst, sn_sss, sn_ssi,sn_ssit,sn_resto        ! informations about the fields to be read
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('sbc_ssr')
	  
	    ! underice tempereature restoring
		DO jj = 1, jpj
			  DO ji = 1, jpi
				 !WRITE(numout,*) 'restoring temp', rn_dqdt, qns(ji,jj) 
				 freez_temp(:,:)=0.0
				 
				 CALL eos_fzp( sss_m(:,:), freez_temp(:,:) )
				 
				 
					  
				 IF (fr_i(ji,jj) > 0.9 .AND. (SUM(ht_i(ji,jj,:)*a_i_b(ji,jj,:)) > 0.45) .AND. sst_m(ji,jj) < (freez_temp(ji,jj))*0.995) THEN
					
					zqrp = -240 * ( sst_m(ji,jj) - (freez_temp(ji,jj))*0.995 )
				 ENDIF
				 
				 qns(ji,jj) = qns(ji,jj) + zqrp
				 qrp(ji,jj) = zqrp
			  END DO
		   END DO
	   CALL iom_put( "freez_point", freez_temp )
	   CALL iom_put( "qrp", freez_temp )                             ! heat flux damping
	  
	  
      !
      IF( nn_sstr + nn_sssr + nn_ssir /= 0 ) THEN
         !
         IF( nn_sstr == 1)   CALL fld_read( kt, nn_fsbc, sf_sst )   ! Read SST data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssi )   ! Read SSI data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssit )   ! Read SSIT data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssit_error)   ! Read SST data and provides it at kt

		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_resto )   ! Read SST data and provides it at kt
         IF( nn_sssr >= 1)   CALL fld_read( kt, nn_fsbc, sf_sss )   ! Read SSS data and provides it at kt
         !
         !                                         ! ========================= !
         IF( MOD( kt-1, nn_fsbc ) == 0 ) THEN      !    Add restoring term     !
            !                                      ! ========================= !
            !
            IF( nn_sstr == 1 ) THEN                                   !* Temperature restoring term
               DO jj = 1, jpj
                  DO ji = 1, jpi
					 !WRITE(numout,*) 'restoring temp', rn_dqdt, qns(ji,jj) 
                     zqrp = rn_dqdt * ( sst_m(ji,jj) - sf_sst(1)%fnow(ji,jj,1) )
                     qns(ji,jj) = qns(ji,jj) + zqrp
                     qrp(ji,jj) = zqrp
                  END DO
               END DO
               !CALL iom_put( "qrp", qrp )                             ! heat flux damping
            ENDIF
            !
			
					
            IF( nn_sssr == 1 ) THEN                                   !* Salinity damping term (salt flux only (sfx))
               zsrp = rn_deds / rday                                  ! from [mm/day] to [kg/m2/s]
!CDIR COLLAPSE
               DO jj = 1, jpj
                  DO ji = 1, jpi
                     zerp = zsrp * ( 1. - 2.*rnfmsk(ji,jj) )   &      ! No damping in vicinity of river mouths
                        &        * ( sss_m(ji,jj) - sf_sss(1)%fnow(ji,jj,1) ) 
                     sfx(ji,jj) = sfx(ji,jj) + zerp                 ! salt flux
                     erp(ji,jj) = zerp / MAX( sss_m(ji,jj), 1.e-20 ) ! converted into an equivalent volume flux (diagnostic only)
                  END DO
               END DO
               !CALL iom_put( "erp", erp )                             ! freshwater flux damping
               !
            ELSEIF( nn_sssr == 2 ) THEN                               !* Salinity damping term (volume flux (emp) and associated heat flux (qns)
               zsrp = rn_deds / rday                                  ! from [mm/day] to [kg/m2/s]
               zerp_bnd = rn_sssr_bnd / rday                          !       -              -    
!CDIR COLLAPSE
               DO jj = 1, jpj
                  DO ji = 1, jpi                            
                     zerp = zsrp * ( 1. - 2.*rnfmsk(ji,jj) )   &      ! No damping in vicinity of river mouths
                        &        * ( sss_m(ji,jj) - sf_sss(1)%fnow(ji,jj,1) )   &
                        &        / MAX(  sss_m(ji,jj), 1.e-20   )
                     IF( ln_sssr_bnd )   zerp = SIGN( 1., zerp ) * MIN( zerp_bnd, ABS(zerp) )
                     emp(ji,jj) = emp (ji,jj) + zerp
                     qns(ji,jj) = qns(ji,jj) - zerp * rcp * sst_m(ji,jj)
                     erp(ji,jj) = zerp
                  END DO
               END DO
              ! CALL iom_put( "erp", erp )                             ! freshwater flux damping
            ENDIF
            !
         ENDIF
         !
      ENDIF
      !
      IF( nn_timing == 1 )  CALL timing_stop('sbc_ssr')
      !
   END SUBROUTINE sbc_ssr

  SUBROUTINE sbc_ssr_ice( kt )
  

  
  !!---------------------------------------------------------------------
      !!                     ***  ROUTINE sbc_ssr_ice  ***
     
      !!---------------------------------------------------------------------
      INTEGER, INTENT(in   ) ::   kt   ! ocean time step
      !!
      INTEGER  ::   ji, jj   ! dummy loop indices
      REAL(wp) ::   zqrp_melt     ! local scalar for heat flux damping
      REAL(wp) ::   icethic_temporary,icethi    ! local scalar for ice thickness sum over categories
	  REAL(wp) ::   ice_conc_diff,abs_ice_conc_diff 
	  REAL(wp) ::   zqrp_freez, tmp_thic_diff,thic_error    ! local scalar for heat flux damping
      INTEGER  ::   ierror   ! return error code
      !!
      CHARACTER(len=100) ::  cn_dir          ! Root directory for location of ssr files
      TYPE(FLD_N) ::   sn_ssi,sn_ssit,sn_resto        ! informations about the fields to be read
	  
	  
      !!----------------------------------------------------------------------
      !
	  
	  
      IF( nn_timing == 1 )  CALL timing_start('sbc_ssr_ice')
	  
	  !WRITE(*,*) 'ICE REST'
# if defined key_lim3
      !
      IF( nn_ssir /= 0 ) THEN
         !
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssi )   ! Read SSI conc data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssit )   ! Read SSI thickness data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_ssit_error )   ! Read SSI thinckness error data and provides it at kt
		 IF( nn_ssir == 1)   CALL fld_read( kt, nn_fsbc, sf_resto )   ! Read SST data and provides it at kt

         !
         !                                         ! ========================= !
         IF( MOD( kt-1, nn_fsbc ) == 0 ) THEN      !    Add restoring term     !
            !                                      ! ========================= !
            !

			
			IF( nn_ssir == 1 ) THEN  !* Ice concentration restoring term
			   DO jj = 1, jpj
				  DO ji = 1, jpi
				  ! Skip all NANs
					ice_resto_mask=sf_resto(1)%fnow(ji,jj,1)
					IF (ice_resto_mask .NE. ice_resto_mask) THEN
						CONTINUE
					ENDIF
					ice_resto_conc=sf_ssi(1)%fnow(ji,jj,1)
					IF (ice_resto_conc .NE. ice_resto_conc) THEN
						CONTINUE
					ENDIF
					ice_resto_thic=sf_ssit(1)%fnow(ji,jj,1)
					! If conc ok, we skip only thickness resto
					IF (ice_resto_thic .NE. ice_resto_thic) THEN
						ice_resto_thic=0
					ENDIF
					IF (ice_resto_mask > 1) THEN
						ice_resto_mask=0
					ENDIF
				  ice_conc_diff=((( fr_i(ji,jj) - ice_resto_conc/100 )*100.0))
				  abs_ice_conc_diff=ABS(ice_conc_diff)

						IF (abs_ice_conc_diff > 10.0 .AND. ice_conc_diff>0.0 ) THEN !if ice must be melted
							 zqrp_melt = rn_dqdi_melt * ice_conc_diff
							 qsr_ice(ji,jj,:) = qsr_ice(ji,jj,:) + zqrp_melt*ice_resto_mask
						ENDIF
						
						IF (abs_ice_conc_diff > 5.0 .AND. ice_conc_diff<0.0 ) THEN !if ice must be freezed
							zqrp_freez = rn_dqdi_freez * ice_conc_diff
							qns_oce (ji,jj)= qns_oce (ji,jj) + zqrp_freez*ice_resto_mask
						ENDIF

					
					IF (ice_resto_thic>0.05) THEN
							icethic_temporary = SUM(ht_i(ji,jj,:)*a_i_b(ji,jj,:))
							
							tmp_thic_diff = ((icethic_temporary - ice_resto_thic ))
							thic_error=sf_ssit_error(1)%fnow(ji,jj,1)
							IF (ABS(thic_error)<0.1 .OR. (thic_error .NE. thic_error) .OR. (thic_error<0.01)) THEN 
								thic_error=0.1 
							ENDIF
							
							zqrp_freez=0
							zqrp_melt=0
						IF ((abs_ice_conc_diff<0.1) .AND. (fr_i(ji,jj)>0.7)) THEN
							IF (ABS(tmp_thic_diff)>thic_error .AND. (tmp_thic_diff<0.0) ) THEN !if ice must be thickness-freezed 
								zqrp_freez = rn_dqdi_thick_freez * (tmp_thic_diff )*100.0
								qsr_ice (ji,jj,:)= qsr_ice (ji,jj,:) + zqrp_freez*ice_resto_mask
							ENDIF
							
							IF (ABS(tmp_thic_diff)>thic_error .AND. (tmp_thic_diff>0.0) ) THEN !if ice must be thickness-melted 
								zqrp_melt = rn_dqdi_thick_melt * (tmp_thic_diff )*100.0
								qsr_ice (ji,jj,:)= qsr_ice (ji,jj,:) + zqrp_melt*ice_resto_mask
							ENDIF
							ENDIF
					ENDIF
					
                  END DO
               END DO
            ENDIF
			
		 DO jj = 1, jpj
                   DO ji = 1, jpi
				   icethi = SUM(ht_i(ji,jj,:)*a_i_b(ji,jj,:))
					 IF (icethi  > 6.0 ) THEN !ice thickness anomaly exists				
						 zqrp_melt = 10 * ( icethi -6.0 )*100.0
						 qsr_ice(ji,jj,:) = qsr_ice(ji,jj,:) + zqrp_melt
						 ht_i(ji,jj,:) = 1.0
					 ENDIF
			      END DO
             END DO
			
            !
         ENDIF
         !
      ENDIF
	  
	  
# endif
      !
      IF( nn_timing == 1 )  CALL timing_stop('sbc_ssr')
	        !
   END SUBROUTINE sbc_ssr_ice
   
   SUBROUTINE sbc_ssr_init
      !!---------------------------------------------------------------------
      !!                  ***  ROUTINE sbc_ssr_init  ***
      !!
      !! ** Purpose :   initialisation of surface damping term
      !!
      !! ** Method  : - Read namelist namsbc_ssr
      !!              - Read observed SST and/or SSS if required
      !!---------------------------------------------------------------------
      INTEGER  ::   ji, jj   ! dummy loop indices
      REAL(wp) ::   zerp     ! local scalar for evaporation damping
      REAL(wp) ::   zqrp     ! local scalar for heat flux damping
      REAL(wp) ::   zsrp     ! local scalar for unit conversion of rn_deds factor
      REAL(wp) ::   zerp_bnd ! local scalar for unit conversion of rn_epr_max factor
      INTEGER  ::   ierror   ! return error code
	  INTEGER  ::   inum
      !!
      CHARACTER(len=100) ::  cn_dir          ! Root directory for location of ssr files
      TYPE(FLD_N) ::   sn_sst, sn_sss, sn_ssi, sn_ssit,sn_ssit_error,sn_resto        ! informations about the fields to be read
      NAMELIST/namsbc_ssr/ cn_dir, nn_sstr, nn_ssir, nn_sssr, rn_dqdt, rn_dqdi_melt, rn_dqdi_freez,rn_dqdi_thick_melt, rn_dqdi_thick_freez, rn_deds, sn_sst, sn_sss, sn_ssi,sn_ssit,sn_ssit_error,sn_resto, ln_sssr_bnd, rn_sssr_bnd
      INTEGER     ::  ios
      !!----------------------------------------------------------------------
      !
 
      REWIND( numnam_ref )              ! Namelist namsbc_ssr in reference namelist : 
      READ  ( numnam_ref, namsbc_ssr, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namsbc_ssr in reference namelist', lwp )

      REWIND( numnam_cfg )              ! Namelist namsbc_ssr in configuration namelist :
      READ  ( numnam_cfg, namsbc_ssr, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namsbc_ssr in configuration namelist', lwp )
      IF(lwm) WRITE ( numond, namsbc_ssr )

      IF(lwp) THEN                 !* control print
         WRITE(numout,*)
         WRITE(numout,*) 'sbc_ssr : SST and/or SSS and/or SSI damping term '
         WRITE(numout,*) '~~~~~~~ '
         WRITE(numout,*) '   Namelist namsbc_ssr :'
         WRITE(numout,*) '      SST restoring term (Yes=1)             nn_sstr     = ', nn_sstr
		 WRITE(numout,*) '      SSI restoring term (Yes=1)             nn_ssti     = ', nn_ssir
         WRITE(numout,*) '      SSS damping term (Yes=1, salt flux)    nn_sssr     = ', nn_sssr
         WRITE(numout,*) '                       (Yes=2, volume flux) '
         WRITE(numout,*) '      dQ/dT (restoring magnitude on SST)     rn_dqdt     = ', rn_dqdt, ' W/m2/K'
		 WRITE(numout,*) '      dQ/d% (restoring magnitude on SSI)     rn_dqdi_melt     = ', rn_dqdi_melt, ' W/m2/%' 
		 WRITE(numout,*) '      dQ/d% (restoring magnitude on SSI)     rn_dqdi_freez     = ', rn_dqdi_freez, ' W/m2/%'
		 WRITE(numout,*) '      dQ/dTh (restoring magnitude on SSI)     rn_dqdi_thick_melt     = ', rn_dqdi_thick_melt, ' W/m2/%' 
		 WRITE(numout,*) '      dQ/dTh (restoring magnitude on SSI)     rn_dqdi_thick_freez     = ', rn_dqdi_thick_freez, ' W/m2/%'
         WRITE(numout,*) '      dE/dS (restoring magnitude on SSS)     rn_deds     = ', rn_deds, ' mm/day'
         WRITE(numout,*) '      flag to bound erp term                 ln_sssr_bnd = ', ln_sssr_bnd
         WRITE(numout,*) '      ABS(Max./Min.) erp threshold           rn_sssr_bnd = ', rn_sssr_bnd, ' mm/day'
      ENDIF
      !
      !                            !* Allocate erp and qrp array
      ALLOCATE( qrp(jpi,jpj), erp(jpi,jpj), freez_temp(jpi,jpj),  STAT=ierror )
      IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate erp and qrp array' )
      !
      IF( nn_sstr == 1 ) THEN      !* set sf_sst structure & allocate arrays
         !
         ALLOCATE( sf_sst(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sst structure' )
         ALLOCATE( sf_sst(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sst now array' )
         !
         ! fill sf_sst with sn_sst and control print
         CALL fld_fill( sf_sst, (/ sn_sst /), cn_dir, 'sbc_ssr', 'SST restoring term toward SST data', 'namsbc_ssr' )
         IF( sf_sst(1)%ln_tint )   ALLOCATE( sf_sst(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sst data array' )
         !
      ENDIF
	  
# if defined key_lim3
	  IF( nn_ssir == 1 ) THEN      !* set sf_ssi structure & allocate arrays
         !
		 
         ALLOCATE( sf_ssi(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssi structure' )
         ALLOCATE( sf_ssi(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssi now array' )
         !
         ! fill sf_ssi with sn_ssi and control print
         CALL fld_fill( sf_ssi, (/ sn_ssi /), cn_dir, 'sbc_ssr', 'SSI restoring term toward SSI data', 'namsbc_ssr' )
         IF( sf_ssi(1)%ln_tint )   ALLOCATE( sf_ssi(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssi data array' )
		 
		 ALLOCATE( sf_ssit(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssi structure' )
         ALLOCATE( sf_ssit(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssi now array' )
		 
		 ALLOCATE( sf_ssit_error(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssit_error structure' )
         ALLOCATE( sf_ssit_error(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssit_error now array' )
		 
		 ALLOCATE( sf_resto(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_resto structure' )
         ALLOCATE( sf_resto(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_resto now array' )
         !
         ! fill sf_ssit with sn_ssit and control print
         CALL fld_fill( sf_ssit, (/ sn_ssit /), cn_dir, 'sbc_ssr', 'SSI restoring term toward SSI data', 'namsbc_ssr' )
         IF( sf_ssit(1)%ln_tint )   ALLOCATE( sf_ssit(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssit data array' )
		 
		 CALL fld_fill( sf_ssit_error, (/ sn_ssit_error /), cn_dir, 'sbc_ssr', 'SSI error for SSI restoring term', 'namsbc_ssr' )
         IF( sf_ssit(1)%ln_tint )   ALLOCATE( sf_ssit_error(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_ssit_error data array' )
		 
		 CALL fld_fill( sf_resto, (/ sn_resto /), cn_dir, 'sbc_ssr', 'Resto mask restoring term toward resto mask data', 'namsbc_ssr' )
         IF( sf_resto(1)%ln_tint )   ALLOCATE( sf_resto(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_resto data array' )
		 
         !
      ENDIF
# endif
      !
      IF( nn_sssr >= 1 ) THEN      !* set sf_sss structure & allocate arrays
         !
         ALLOCATE( sf_sss(1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sss structure' )
         ALLOCATE( sf_sss(1)%fnow(jpi,jpj,1), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sss now array' )
         !
         ! fill sf_sss with sn_sss and control print
         CALL fld_fill( sf_sss, (/ sn_sss /), cn_dir, 'sbc_ssr', 'SSS restoring term toward SSS data', 'namsbc_ssr' )
         IF( sf_sss(1)%ln_tint )   ALLOCATE( sf_sss(1)%fdta(jpi,jpj,1,2), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'sbc_ssr: unable to allocate sf_sss data array' )
         !
      ENDIF
      !
      !                            !* Initialize qrp and erp if no restoring 
      IF( nn_sstr /= 1                   )   qrp(:,:) = 0._wp
	  IF( nn_ssir /= 1                   )   qrp_ice(:,:) = 0._wp
      IF( nn_sssr /= 1 .OR. nn_sssr /= 2 )   erp(:,:) = 0._wp
      !
   END SUBROUTINE sbc_ssr_init
      
   !!======================================================================
END MODULE sbcssr
