!
! Copyright (C) 2003-2013 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!


!----------------------------------------------------------------------------
SUBROUTINE rdiaghg( n, m, h, s, ldh, e, v )
  !----------------------------------------------------------------------------
  ! ... Hv=eSv, with H symmetric matrix, S overlap matrix.
  ! ... On output both matrix are unchanged
  !
  ! ... LAPACK version - uses both DSYGV and DSYGVX
  !
  USE la_param,          ONLY : DP
  USE mp,                ONLY : mp_bcast
  USE mp_bands_util,     ONLY : me_bgrp, root_bgrp, intra_bgrp_comm
  !
  IMPLICIT NONE
  !
  INTEGER, INTENT(IN) :: n, m, ldh
    ! dimension of the matrix to be diagonalized
    ! number of eigenstates to be calculated
    ! leading dimension of h, as declared in the calling pgm unit
  REAL(DP), INTENT(INOUT) :: h(ldh,n), s(ldh,n)
    ! matrix to be diagonalized
    ! overlap matrix
  !
  REAL(DP), INTENT(OUT) :: e(n)
    ! eigenvalues
  REAL(DP), INTENT(OUT) :: v(ldh,m)
    ! eigenvectors (column-wise)
  !
  INTEGER               :: lwork, nb, mm, info, i, j
    ! mm = number of calculated eigenvectors
  REAL(DP)              :: abstol
  REAL(DP), PARAMETER   :: one = 1_DP
  REAL(DP), PARAMETER   :: zero = 0_DP
  INTEGER,  ALLOCATABLE :: iwork(:), ifail(:)
  REAL(DP), ALLOCATABLE :: work(:), sdiag(:), hdiag(:)
  LOGICAL               :: all_eigenvalues
  INTEGER,  EXTERNAL    :: ILAENV
    ! ILAENV returns optimal block size "nb"
  !
  CALL start_clock( 'rdiaghg' )
  !
  ! ... only the first processor diagonalize the matrix
  !
  IF ( me_bgrp == root_bgrp ) THEN
     !
     ! ... save the diagonal of input S (it will be overwritten)
     !
     ALLOCATE( sdiag( n ) )
     DO i = 1, n
        sdiag(i) = s(i,i)
     END DO
     !
     all_eigenvalues = ( m == n )
     !
     ! ... check for optimal block size
     !
     nb = ILAENV( 1, 'DSYTRD', 'U', n, -1, -1, -1 )
     !
     IF ( nb < 5 .OR. nb >= n ) THEN
        !
        lwork = 8*n
        !
     ELSE
        !
        lwork = ( nb + 3 )*n
        !
     END IF
     !
     ALLOCATE( work( lwork ) )
     !
     IF ( all_eigenvalues ) THEN
        !
        ! ... calculate all eigenvalues
        !
        !$omp parallel do
        do i =1, n
           v(1:ldh,i) = h(1:ldh,i)
        end do
        !$omp end parallel do
        !
#if defined (__ESSL)
        !
        ! ... there is a name conflict between essl and lapack ...
        !
        CALL DSYGV( 1, v, ldh, s, ldh, e, v, ldh, n, work, lwork )
        !
        info = 0
#else
        CALL DSYGV( 1, 'V', 'U', n, v, ldh, s, ldh, e, work, lwork, info )
#endif
        !
     ELSE
        !
        ! ... calculate only m lowest eigenvalues
        !
        ALLOCATE( iwork( 5*n ) )
        ALLOCATE( ifail( n ) )
        !
        ! ... save the diagonal of input H (it will be overwritten)
        !
        ALLOCATE( hdiag( n ) )
        DO i = 1, n
           hdiag(i) = h(i,i)
        END DO
        !
        abstol = 0.D0
       ! abstol = 2.D0*DLAMCH( 'S' )
        !
        CALL DSYGVX( 1, 'V', 'I', 'U', n, h, ldh, s, ldh, &
                     0.D0, 0.D0, 1, m, abstol, mm, e, v, ldh, &
                     work, lwork, iwork, ifail, info )
        !
        DEALLOCATE( ifail )
        DEALLOCATE( iwork )
        !
        ! ... restore input H matrix from saved diagonal and lower triangle
        !
        !$omp parallel do
        DO i = 1, n
           h(i,i) = hdiag(i)
           DO j = i + 1, n
              h(i,j) = h(j,i)
           END DO
           DO j = n + 1, ldh
              h(j,i) = 0.0_DP
           END DO
        END DO
        !$omp end parallel do
        !
        DEALLOCATE( hdiag )
        !
     END IF
     !
     DEALLOCATE( work )
     !
     IF ( info > n ) THEN
        CALL errore( 'rdiaghg', 'S matrix not positive definite', ABS( info ) )
     ELSE IF ( info > 0 ) THEN
        CALL errore( 'rdiaghg', 'eigenvectors failed to converge', ABS( info ) )
     ELSE IF ( info < 0 ) THEN
        CALL errore( 'rdiaghg', 'incorrect call to DSYGV*', ABS( info ) )
     END IF
     
     ! ... restore input S matrix from saved diagonal and lower triangle
     !
     !$omp parallel do
     DO i = 1, n
        s(i,i) = sdiag(i)
        DO j = i + 1, n
           s(i,j) = s(j,i)
        END DO
        DO j = n + 1, ldh
           s(j,i) = 0.0_DP
        END DO
     END DO
     !$omp end parallel do
     !
     DEALLOCATE( sdiag )
     !
  END IF
  !
  ! ... broadcast eigenvectors and eigenvalues to all other processors
  !
  CALL mp_bcast( e, root_bgrp, intra_bgrp_comm )
  CALL mp_bcast( v, root_bgrp, intra_bgrp_comm )
  !
  CALL stop_clock( 'rdiaghg' )
  !
  RETURN
  !
END SUBROUTINE rdiaghg


#if defined(__CUDA)
!----------------------------------------------------------------------------
SUBROUTINE rdiaghg_gpu( n, m, h_d, s_d, ldh, e_d, v_d )
  !----------------------------------------------------------------------------
  ! ... Hv=eSv, with H symmetric matrix, S overlap matrix.
  ! ... On output both matrix are unchanged
  !
  USE cudafor
  USE dsygvdx_gpu
  USE la_param,          ONLY : DP
  USE mp,                ONLY : mp_bcast
  USE mp_bands_util,     ONLY : me_bgrp, root_bgrp, intra_bgrp_comm
  !
  IMPLICIT NONE
  !
  INTEGER, INTENT(IN) :: n, m, ldh
    ! dimension of the matrix to be diagonalized
    ! number of eigenstates to be calculated
    ! leading dimension of h, as declared in the calling pgm unit
  REAL(DP), DEVICE, INTENT(INOUT) :: h_d(ldh,n), s_d(ldh,n)
    ! matrix to be diagonalized, allocated on the device
    ! overlap matrix, allocated on the device
  !
  REAL(DP), DEVICE, INTENT(OUT) :: e_d(n)
    ! eigenvalues, allocated on the device
  REAL(DP), DEVICE, INTENT(OUT) :: v_d(ldh, n)
    ! eigenvectors (column-wise), allocated on the device
  !
  INTEGER               :: lwork, nb, mm, info, i, j
    ! mm = number of calculated eigenvectors
  REAL(DP)              :: abstol
  REAL(DP), PARAMETER   :: one = 1_DP
  REAL(DP), PARAMETER   :: zero = 0_DP
  INTEGER,  ALLOCATABLE :: iwork(:), ifail(:)
  REAL(DP), ALLOCATABLE :: work(:), sdiag(:), hdiag(:)

  ATTRIBUTES( PINNED )          :: work, iwork
  REAL(DP), ALLOCATABLE, PINNED :: v_h(:,:)
  REAL(DP), ALLOCATABLE, PINNED :: e_h(:)
  !
  INTEGER                       :: lwork_d, liwork
  REAL(DP), ALLOCATABLE, DEVICE :: work_d(:)
  !  
  ! Temp arrays to save H and S.
  REAL(DP), ALLOCATABLE, DEVICE :: h_diag_d(:), s_diag_d(:)
  !
  CALL start_clock( 'rdiaghg_gpu' )
  !
  ! ... only the first processor diagonalize the matrix
  !
  IF ( me_bgrp == root_bgrp ) THEN
     !
     ALLOCATE(e_h(n), v_h(ldh,n))
     !
     ALLOCATE(h_diag_d(n), s_diag_d(n))
     !$cuf kernel do(1) <<<*,*>>>
     DO i = 1, n
        h_diag_d(i) = DBLE( h_d(i,i) )
        s_diag_d(i) = DBLE( s_d(i,i) )
     END DO
     ! 
     lwork  = 1 + 6*n + 2*n*n
     liwork = 3 + 5*n
     ALLOCATE(work(lwork), iwork(liwork))
     !
     lwork_d = 2*64*64 + 66*n
     ALLOCATE(work_d(1*lwork_d), STAT = info)
     IF( info /= 0 ) CALL errore( ' rdiaghg_gpu ', ' allocate work_d ', ABS( info ) )
     !
     CALL dsygvdx_gpu(n, h_d, ldh, s_d, ldh, v_d, ldh, 1, m, e_d, work_d, &
                      lwork_d, work, lwork, iwork, liwork, v_h, size(v_h, 1), &
                      e_h, info, .TRUE.)
     !
     IF( info /= 0 ) CALL errore( ' rdiaghg_gpu ', ' dsygvdx_gpu failed ', ABS( info ) )
     !
!$cuf kernel do(1) <<<*,*>>>
     DO i = 1, n
        h_d(i,i) = h_diag_d(i)
        s_d(i,i) = s_diag_d(i)
        DO j = i + 1, n
           h_d(i,j) = h_d(j,i)
           s_d(i,j) = s_d(j,i)
        END DO
        ! This could be avoided, need to check dsygvdx_gpu implementation
        DO j = n + 1, ldh
           h_d(j,i) = 0.0_DP
           s_d(j,i) = 0.0_DP
        END DO
     END DO
     DEALLOCATE(h_diag_d,s_diag_d)
     ! 
     DEALLOCATE(work, iwork)
     DEALLOCATE(work_d)
     
     DEALLOCATE(v_h, e_h)
  END IF
  !
  ! ... broadcast eigenvectors and eigenvalues to all other processors
  !
  CALL mp_bcast( e_d(1:n), root_bgrp, intra_bgrp_comm )
  CALL mp_bcast( v_d(1:ldh, 1:m), root_bgrp, intra_bgrp_comm )
  !
  CALL stop_clock( 'rdiaghg_gpu' )
  !
  RETURN
  !
END SUBROUTINE rdiaghg_gpu
#endif
!
!----------------------------------------------------------------------------
SUBROUTINE prdiaghg( n, h, s, ldh, e, v, desc )
  !----------------------------------------------------------------------------
  !
  ! ... calculates eigenvalues and eigenvectors of the generalized problem
  ! ... Hv=eSv, with H symmetric matrix, S overlap matrix.
  ! ... On output both matrix are unchanged
  !
  ! ... Parallel version with full data distribution
  !
  USE la_param,          ONLY : DP
  USE mp,                ONLY : mp_bcast
  USE descriptors,       ONLY : la_descriptor
  USE mp_diag,           ONLY : ortho_parent_comm
#if defined __SCALAPACK
  USE mp_diag,           ONLY : ortho_cntx, me_blacs, np_ortho, me_ortho, ortho_comm
  USE dspev_module,      ONLY : pdsyevd_drv
#endif
  !
  !
  IMPLICIT NONE
  !
  INTEGER, INTENT(IN) :: n, ldh
    ! dimension of the matrix to be diagonalized and number of eigenstates to be calculated
    ! leading dimension of h, as declared in the calling pgm unit
  REAL(DP), INTENT(INOUT) :: h(ldh,ldh), s(ldh,ldh)
    ! matrix to be diagonalized
    ! overlap matrix
  !
  REAL(DP), INTENT(OUT) :: e(n)
    ! eigenvalues
  REAL(DP), INTENT(OUT) :: v(ldh,ldh)
    ! eigenvectors (column-wise)
  TYPE(la_descriptor), INTENT(IN) :: desc
  !
  INTEGER, PARAMETER    :: root = 0
  INTEGER               :: nx
    ! local block size
  REAL(DP), PARAMETER   :: one = 1_DP
  REAL(DP), PARAMETER   :: zero = 0_DP
  REAL(DP), ALLOCATABLE :: hh(:,:)
  REAL(DP), ALLOCATABLE :: ss(:,:)
#if defined(__SCALAPACK)
  INTEGER     :: desch( 16 ), info
#endif
  INTEGER               :: i
  !
  CALL start_clock( 'rdiaghg' )
  !
  IF( desc%active_node > 0 ) THEN
     !
     nx   = desc%nrcx
     !
     IF( nx /= ldh ) &
        CALL errore(" prdiaghg ", " inconsistent leading dimension ", ldh )
     !
     ALLOCATE( hh( nx, nx ) )
     ALLOCATE( ss( nx, nx ) )
     !
     !$omp parallel do
     do i=1,nx
        hh(1:nx,i) = h(1:nx,i)
        ss(1:nx,i) = s(1:nx,i)
     end do
     !$omp end parallel do
     !
  END IF
  !
  CALL start_clock( 'rdiaghg:choldc' )
  !
  ! ... Cholesky decomposition of s ( L is stored in s )
  !
  IF( desc%active_node > 0 ) THEN
     !
#if defined(__SCALAPACK)
     CALL descinit( desch, n, n, desc%nrcx, desc%nrcx, 0, 0, ortho_cntx, SIZE( hh, 1 ) , info )
  
     IF( info /= 0 ) CALL errore( ' rdiaghg ', ' descinit ', ABS( info ) )
#endif
     !
#if defined(__SCALAPACK)
     CALL PDPOTRF( 'L', n, ss, 1, 1, desch, info )
     IF( info /= 0 ) CALL errore( ' rdiaghg ', ' problems computing cholesky ', ABS( info ) )
#else
     CALL qe_pdpotrf( ss, nx, n, desc )
#endif
     !
  END IF
  !
  CALL stop_clock( 'rdiaghg:choldc' )
  !
  ! ... L is inverted ( s = L^-1 )
  !
  CALL start_clock( 'rdiaghg:inversion' )
  !
  IF( desc%active_node > 0 ) THEN
     !
#if defined(__SCALAPACK)
     ! 
     CALL sqr_dsetmat( 'U', n, zero, ss, size(ss,1), desc )

     CALL PDTRTRI( 'L', 'N', n, ss, 1, 1, desch, info )
     !
     IF( info /= 0 ) CALL errore( ' rdiaghg ', ' problems computing inverse ', ABS( info ) )
#else
     CALL qe_pdtrtri ( ss, nx, n, desc )
#endif
     !
  END IF
  !
  CALL stop_clock( 'rdiaghg:inversion' )
  !
  ! ... v = L^-1*H
  !
  CALL start_clock( 'rdiaghg:paragemm' )
  !
  IF( desc%active_node > 0 ) THEN
     !
     CALL sqr_mm_cannon( 'N', 'N', n, ONE, ss, nx, hh, nx, ZERO, v, nx, desc )
     !
  END IF
  !
  ! ... h = ( L^-1*H )*(L^-1)^T
  !
  IF( desc%active_node > 0 ) THEN
     !
     CALL sqr_mm_cannon( 'N', 'T', n, ONE, v, nx, ss, nx, ZERO, hh, nx, desc )
     !
  END IF
  !
  CALL stop_clock( 'rdiaghg:paragemm' )
  !
  IF ( desc%active_node > 0 ) THEN
     ! 
     !  Compute local dimension of the cyclically distributed matrix
     !
#if defined(__SCALAPACK)
     CALL pdsyevd_drv( .true., n, desc%nrcx, hh, SIZE(hh,1), e, ortho_cntx, ortho_comm )
#else
     CALL qe_pdsyevd( .true., n, desc, hh, SIZE(hh,1), e )
#endif
     !
  END IF
  !
  ! ... v = (L^T)^-1 v
  !
  CALL start_clock( 'rdiaghg:paragemm' )
  !
  IF ( desc%active_node > 0 ) THEN
     !
     CALL sqr_mm_cannon( 'T', 'N', n, ONE, ss, nx, hh, nx, ZERO, v, nx, desc )
     !
     DEALLOCATE( ss )
     DEALLOCATE( hh )
     !
  END IF
  !
  CALL mp_bcast( e, root, ortho_parent_comm )
  !
  CALL stop_clock( 'rdiaghg:paragemm' )
  !
  CALL stop_clock( 'rdiaghg' )
  !
  RETURN
  !
END SUBROUTINE prdiaghg
