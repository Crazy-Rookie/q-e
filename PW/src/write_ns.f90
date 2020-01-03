!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
SUBROUTINE write_ns
  !-----------------------------------------------------------------------
  !! Prints on output ns infos.
  !
  USE kinds,      ONLY : DP
  USE constants,  ONLY : rytoev
  USE ions_base,  ONLY : nat, ntyp => nsp, ityp
  USE lsda_mod,   ONLY : nspin
  USE io_global,  ONLY : stdout
  USE scf,        ONLY : rho
  USE ldaU,       ONLY : Hubbard_lmax, Hubbard_l, Hubbard_U, Hubbard_J, &
                         Hubbard_alpha, lda_plus_u_kind, Hubbard_J0,    &
                         Hubbard_beta
  !
  IMPLICIT NONE
  !
  INTEGER :: is, na, nt, m1, m2, ldim
  ! counter on spin component
  ! counters on atoms and their type
  ! counters on d components
  INTEGER, PARAMETER :: ldmx = 7
  COMPLEX(DP) :: f(ldmx,ldmx), vet(ldmx,ldmx)
  REAL(DP) :: lambda(ldmx), nsum, nsuma(2)
  !
  WRITE (stdout,*) '--- enter write_ns ---'
  !
  IF ( 2*Hubbard_lmax+1 > ldmx ) CALL errore( 'write_ns', 'ldmx is too small', 1 )
  !
  ! ... output of +U parameters
  !
  WRITE (stdout,*) 'LDA+U parameters:'
  !
  IF (lda_plus_u_kind == 0) THEN
     !
     DO nt = 1, ntyp
        IF (Hubbard_U(nt) /= 0.d0 .OR. Hubbard_alpha(nt) /= 0.d0) THEN
           IF (Hubbard_J0(nt) /= 0.d0 .OR. Hubbard_beta(nt) /=0.d0) THEN
              WRITE(stdout,'(a,i2,a,f12.8)') 'U(',nt,')     =', Hubbard_U(nt)*rytoev 
              WRITE(stdout,'(a,i2,a,f12.8)') 'J0(',nt,')     =', Hubbard_J0(nt)*rytoev 
              WRITE(stdout,'(a,i2,a,f12.8)') 'alpha(',nt,') =', Hubbard_alpha(nt)*rytoev
              WRITE(stdout,'(a,i2,a,f12.8)') 'beta(',nt,') =', Hubbard_beta(nt)*rytoev
           ELSE
              WRITE(stdout,'(a,i2,a,f12.8)') 'U(',nt,')     =', Hubbard_U(nt)*rytoev
              WRITE(stdout,'(a,i2,a,f12.8)') 'alpha(',nt,') =', Hubbard_alpha(nt)*rytoev
           ENDIF
        ENDIF
     ENDDO
     !
  ELSE
     !
     DO nt = 1, ntyp
        IF (Hubbard_U(nt) /= 0.d0) THEN
           IF (Hubbard_l(nt) == 0) THEN
              WRITE(stdout,'(a,i2,a,f12.8)') 'U(',nt,') =', Hubbard_U(nt) * rytoev
           ELSEIF (Hubbard_l(nt) == 1) THEN
              WRITE(stdout,'(2(a,i3,a,f9.4,3x))') 'U(',nt,') =', Hubbard_U(nt)*rytoev, &
                                                  'J(',nt,') =', Hubbard_J(1,nt)*rytoev
           ELSEIF (Hubbard_l(nt) == 2) THEN
              WRITE(stdout,'(3(a,i3,a,f9.4,3x))') 'U(',nt,') =', Hubbard_U(nt)*rytoev,   &
                                                  'J(',nt,') =', Hubbard_J(1,nt)*rytoev, &
                                                  'B(',nt,') =', Hubbard_J(2,nt)*rytoev
           ELSEIF (Hubbard_l(nt) == 3) THEN
              WRITE(stdout,'(4(a,i3,a,f9.4,3x))') 'U (',nt,') =', Hubbard_U(nt)*rytoev,   &
                                                  'J (',nt,') =', Hubbard_J(1,nt)*rytoev, &
                                                  'E2(',nt,') =', Hubbard_J(2,nt)*rytoev, &
                                                  'E3(',nt,') =', Hubbard_J(3,nt)*rytoev
           ENDIF
        ENDIF
     ENDDO
     !
  ENDIF
  ! 
  !
  nsum = 0.d0
  !
  DO na = 1, nat
     nt = ityp (na)
     IF (Hubbard_U(nt) /= 0.d0 .OR. Hubbard_alpha(nt) /= 0.d0) THEN
        ldim = 2 * Hubbard_l(nt) + 1
        nsuma = 0.d0
        DO is = 1, nspin
           DO m1 = 1, ldim
              nsuma(is) = nsuma(is) + rho%ns(m1,m1,is,na)
           ENDDO
           nsum = nsum + nsuma(is)
        ENDDO
        !
        IF (nspin==1) THEN
           WRITE( stdout,'("atom ",i4,3x,"Tr[ns(na)] = ",f9.5)') &
                              na, 2.d0*nsuma(1)
        ELSE
           WRITE( stdout,'("atom ",i4,3x,"Tr[ns(na)] (up, down, total) = ",3f9.5)') &
                              na, nsuma(1), nsuma(2), nsuma(1)+nsuma(2)
        ENDIF 
        !
        DO is = 1, nspin
           DO m1 = 1, ldim
              DO m2 = 1, ldim
                 f(m1,m2) = rho%ns(m1,m2,is,na)
              ENDDO
           ENDDO
           !
           CALL cdiagh( ldim, f, ldmx, lambda, vet )
           !
           IF (nspin /= 1) write( stdout,'("   spin ",i2)') is
           WRITE( stdout,*) '   eigenvalues: '
           WRITE( stdout,'(7f7.3)') (lambda(m1), m1=1, ldim)
           !
           WRITE( stdout,*) '   eigenvectors:'
           DO m1 = 1, ldim
              WRITE( stdout,'(7f7.3)') ( REAL(vet(m1,m2))**2 + &
                                         AIMAG(vet(m1,m2))**2, m2=1, ldim )
           ENDDO
           !
           WRITE( stdout,*) '   occupations:'
           DO m1 = 1, ldim
              WRITE( stdout,'(7f7.3)') ( DBLE(f(m1,m2)), m2=1, ldim )
           ENDDO
        ENDDO
        !
        IF (nspin /= 1) WRITE( stdout,'("atomic mag. moment = ",f12.6)') &
                               nsuma(1) - nsuma(2) 
     ENDIF
  ENDDO
  !
  IF (nspin==1) nsum = 2.d0 * nsum 
  !
  WRITE( stdout, '(a,1x,f11.6)') 'N of occupied +U levels =', nsum
  WRITE( stdout,*) '--- exit write_ns ---'
  !
  RETURN
  !
END SUBROUTINE write_ns
!
!
!-----------------------------------------------------------------------
SUBROUTINE write_ns_nc
  !-----------------------------------------------------------------------
  !! Prints on output ns infos. Noncollinear version (A. Smogunov).
  !
  USE kinds,             ONLY : DP
  USE constants,         ONLY : rytoev
  USE ions_base,         ONLY : nat, ntyp => nsp, ityp
  USE noncollin_module,  ONLY : npol
  USE io_global,         ONLY : stdout
  USE scf,               ONLY : rho
  USE ldaU,              ONLY : Hubbard_lmax, Hubbard_l, Hubbard_alpha, &
                                Hubbard_U, Hubbard_J
  !
  IMPLICIT NONE
  !
  INTEGER :: is, js, i, na, nt, m1, m2, ldim
  INTEGER, PARAMETER :: ldmx = 7
  COMPLEX(DP) :: f(2*ldmx,2*ldmx), vet(2*ldmx,2*ldmx)
  REAL(DP) :: lambda(2*ldmx), nsum,nsuma(2), ns, mx, my, mz
  !
  WRITE (stdout,*) '--- enter write_ns ---'
  !
  IF ( 2 * Hubbard_lmax + 1 > ldmx ) &
       CALL errore( 'write_ns', 'ldmx is too small', 1 )
  !
  ! ... output of +U parameters
  !
  WRITE (stdout,*) 'LDA+U parameters:'
  !
  DO nt = 1, ntyp
     IF (Hubbard_U(nt) /= 0.d0) THEN
        IF (Hubbard_l(nt)==0) THEN
           WRITE(stdout,'(a,i2,a,f12.8)') 'U(',nt,') =', Hubbard_U(nt) * rytoev
        ELSEIF (Hubbard_l(nt)==1) THEN
           WRITE(stdout,'(2(a,i3,a,f9.4,3x))') 'U(',nt,') =', Hubbard_U(nt)*rytoev, &
                                               'J(',nt,') =', Hubbard_J(1,nt)*rytoev
        ELSEIF (Hubbard_l(nt)==2) THEN
           WRITE(stdout,'(3(a,i3,a,f9.4,3x))') 'U(',nt,') =', Hubbard_U(nt)*rytoev,   &
                                               'J(',nt,') =', Hubbard_J(1,nt)*rytoev, &
                                               'B(',nt,') =', Hubbard_J(2,nt)*rytoev
        ELSEIF (Hubbard_l(nt)==3) THEN
           WRITE(stdout,'(4(a,i3,a,f9.4,3x))') 'U (',nt,') =', Hubbard_U(nt)*rytoev,   &
                                               'J (',nt,') =', Hubbard_J(1,nt)*rytoev, &
                                               'E2(',nt,') =', Hubbard_J(2,nt)*rytoev, &
                                               'E3(',nt,') =', Hubbard_J(3,nt)*rytoev
        ENDIF
     ENDIF
  ENDDO
  !
  !
  nsum = 0.d0
  DO na = 1, nat
     nt = ityp (na)
     IF (Hubbard_U(nt) /= 0.d0 .OR. Hubbard_alpha(nt) /= 0.d0) THEN
        ldim = 2 * Hubbard_l(nt) + 1
        nsuma = 0.d0
        DO is = 1, npol
           i = is**2
           DO m1 = 1, ldim
              nsuma(is) = nsuma(is) + rho%ns_nc(m1,m1,i,na)
           ENDDO
        ENDDO
        nsum = nsum + nsuma(1) + nsuma(2) 
        !
        WRITE( stdout,'("atom ",i4,3x,"Tr[ns(na)] (up, down, total) = ",3f9.5)') &
                              na, nsuma(1), nsuma(2), nsuma(1) + nsuma(2)  
        !
        DO m1 = 1, ldim
           DO m2 = 1, ldim
              f(m1, m2)           = rho%ns_nc(m1,m2,1,na)
              f(m1, ldim+m2)      = rho%ns_nc(m1,m2,2,na)
              f(ldim+m1, m2)      = rho%ns_nc(m1,m2,3,na)
              f(ldim+m1, ldim+m2) = rho%ns_nc(m1,m2,4,na)
           ENDDO
        ENDDO 
        !
        CALL cdiagh( 2*ldim, f, 2*ldmx, lambda, vet )
        !
        WRITE( stdout,*) 'eigenvalues: '
        WRITE( stdout,'(14f7.3)') (lambda(m1), m1=1, 2*ldim)
        !
        WRITE( stdout,*) 'eigenvectors:'
        !
        DO m1 = 1, 2*ldim
          WRITE( stdout,'(14f7.3)') ( REAL(vet(m1,m2))**2 + &
                                      AIMAG(vet(m1,m2))**2, m2=1, 2*ldim )
        ENDDO
        !
        WRITE( stdout,*) 'occupations, | n_(i1, i2)^(sigma1, sigma2) |:'
        !
        DO m1 = 1, 2*ldim
           WRITE( stdout,'(14f7.3)') ( SQRT(REAL(f(m1,m2))**2 + &
                                       AIMAG(f(m1,m2))**2), m2=1, 2*ldim)
        ENDDO
        !
        ! ... calculate the spin moment on +U atom 
        !
        mx = 0.d0
        my = 0.d0
        mz = 0.d0
        DO m1 = 1, 2 * Hubbard_l(nt) + 1
          mx = mx + DBLE( rho%ns_nc(m1,m1,2,na) + rho%ns_nc(m1,m1,3,na) )
          my = my + 2.d0 * AIMAG( rho%ns_nc(m1,m1,2,na) )
          mz = mz + DBLE( rho%ns_nc(m1,m1,1,na) - rho%ns_nc(m1,m1,4,na) )
        ENDDO
        WRITE(stdout,'("atomic mx, my, mz = ",3f12.6)') mx, my, mz
        !
     ENDIF
  ENDDO
  !
  WRITE( stdout, '(a,1x,f11.6)') 'N of occupied +U levels =', nsum
  WRITE( stdout,*) '--- exit write_ns ---'
  !
  RETURN
  !
END SUBROUTINE write_ns_nc
