!
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
! To be used in conjunction with the libmbd library
! library by JH, this wrapper by SG (Luxembourg)

MODULE libmbd_interface

  USE kinds,            ONLY : DP
  USE io_global,        ONLY : stdout  !output file
  USE tsvdw_module,     ONLY : veff_pub, vfree_pub, vdw_isolated !these are used as to not mess with cleanup
  USE ions_base,        ONLY : nat, atm, zv, tau, ntyp => nsp, ityp
  USE cell_base,        ONLY : alat, at, bg, omega  ! at: lattice vectors in real space

  IMPLICIT NONE

  PUBLIC :: mbd_interface
  REAL(dp), PUBLIC :: EmbdvdW

  CONTAINS
    
  SUBROUTINE mbd_interface(tauin, rhor)
  USE mbd,              ONLY: mbd_input_t, mbd_calc_t

  REAL(DP), INTENT(IN) :: rhor(:)
  REAL(DP) :: tauin(3,nat)
  !
  !Variables for libmbd
  !
  INTEGER :: na
  TYPE(mbd_input_t) :: inp
  TYPE(mbd_calc_t) :: calc
  REAL(dp), DIMENSION(:,:), ALLOCATABLE :: mbd_gradient
  REAL(dp), DIMENSION(:), ALLOCATABLE :: ratios
  INTEGER :: code, ierr, my_rank, total
  CHARACTER(200) :: origin, msg
  !
  !Setting up of the variables which depend on atomic numbers
  !
  ALLOCATE(inp%atom_types(nat))
  IF(.NOT.ALLOCATED(mbd_gradient)) ALLOCATE(mbd_gradient(3,nat))
  ALLOCATE(ratios(nat))
  DO na=1,nat
    inp%atom_types(na) = trim(atm(ityp(na)))
    ratios(na)=veff_pub(na)/vfree_pub(ityp(na))
  ENDDO
  !
  !Setting up the variables needed by LibMBD
  !
  inp%coords = tau*alat

  inp%xc = 'pbe'
  call sanity_check_xc_functional_in_use
!  inp%mbd_beta = 0.83  !value is different for different functionals!! TODO

  !
  !Now comes the call to the library
  !
  CALL calc%init(inp)
  CALL calc%get_exception(code, origin, msg)
  IF (code > 0) THEN
    WRITE(stdout,*) msg
    STOP
  ENDIF
  CALL calc%update_vdw_params_from_ratios(ratios)
  CALL calc%evaluate_vdw_method(EmbdvdW)  !Here's the energy
  CALL calc%get_gradients(mbd_gradient) !Here's the gradients
  CALL calc%destroy()

  !
  !TODO: Other parameters and passing them to main subroutines
  !
  !MBD stress to PW/src/stress, MBD forces to PW/src/forces
  !
  !De-allocating the internal variables
  ! 
  IF(ALLOCATED(inp%atom_types)) THEN
    DEALLOCATE(inp%atom_types)
    DEALLOCATE(ratios)
    DEALLOCATE(veff_pub)
!   deallocate(vfree_pub) why dont we need this?? HACK
  ENDIF

  END SUBROUTINE mbd_interface

  SUBROUTINE  sanity_check_xc_functional_in_use()
    USE funct, ONLY : get_dft_short
    IMPLICIT NONE
    select case (TRIM(get_dft_short()))
    CASE ('PBE')
      ! this is a supported xc functional; do nothing...
    CASE DEFAULT
      ! block it off
       CALL errore( 'libmbd_interface', 'current xc functional not yet supported for MBD', 1 )
    END SELECT
    RETURN
  END SUBROUTINE sanity_check_xc_functional_in_use

END MODULE libmbd_interface
