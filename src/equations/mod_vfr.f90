module mod_vfr
  use mod_eqn_setup
  implicit none

  type, extends(equation_t) :: vfr_t
     real, pointer, dimension(:) :: mip
     real, allocatable, dimension(:) :: mfr
   contains
    procedure :: calc_coef_vfr
  end type

contains
! init vfr field
  function construct_vfr(geom,mip,prop) result(eqn)
    implicit none
    type(vfr_t), pointer :: eqn
    type(properties_t) :: prop
    real, target, dimension(:) :: mip
    type(geometry_t) :: geom
    integer :: ne,nbf,length
    type(bc_t), pointer :: bcp

    allocate(eqn)
    length = geom%ne+geom%nbf
    eqn%name='vfr'
    allocate(eqn%phi(length))
    allocate(eqn%phi0(length))
    allocate(eqn%grad(3*length))
    allocate(eqn%mfr(length))
    eqn%mip=>mip
! initialize
    eqn%phi=0.
    eqn%phi0=0.
    eqn%grad=0.
    eqn%mfr=0.
! set BC for vfr
    allocate(eqn%bcs(geom%mg%nintf))
! set BC for vfr
    bcp=>eqn%make_bc(geom,'top');bcp%coef=>lid
    bcp=>eqn%make_bc(geom,'west');bcp%coef=>dirichlet0
    bcp=>eqn%make_bc(geom,'east');bcp%coef=>dirichlet0
    bcp=>eqn%make_bc(geom,'south');bcp%coef=>dirichlet0
    bcp=>eqn%make_bc(geom,'north');bcp%coef=>dirichlet0
    bcp=>eqn%make_bc(geom,'bottom');bcp%coef=>dirichlet0

  end function
! destroy vfr related coef
  subroutine destroy_vfr(eqn)
    implicit none
    type(vfr_t),pointer :: eqn

    deallocate(eqn%bcs,eqn%grad,eqn%phi0,eqn%phi)
    deallocate(eqn)

  end subroutine
! make coef for vfr
  subroutine calc_coef_vfr(eqn,ap,anb,b,geom,prop,dt,ndf,T_bg,rho_bg)
    use mod_util
    use mod_properties
    implicit none
    type(properties_t) :: prop
    type(geometry_t) :: geom
    class(vfr_t) :: eqn
    integer :: e,enb,lfnb,idx,fg,fg_sgn,lf
    real :: dt,DGibbs
    real :: d,f,fnb,sumf,vol,ap(*),anb(*),b(*),sumdefc
    real, dimension(*) :: T_bg,rho_bg,ndf
    real :: area,ap0,wt,ds,J,eta,r_crit
    real, parameter :: z=1.0,pi=3.14,gam=1.4,L=2230,K_b=1.38e-23,R_u=8.3145,M_wat=18
    real, dimension(3) :: dr,norm,rip,rp,rpnb,ghi,gti
    integer :: i,ibc

    do e=1,geom%ne


      DGibbs=prop%sigma(e)*(eqn%phi(e)/ndf(e)*geom%vol(e))
      r_crit=2*prop%sigma(e)/prop%rho(e)/DGibbs
      eta=2*(gam-1)/(gam+1)*L/R_u/T_bg(e)*(L/R_u/T_bg(e)-0.5)
      J=z/(1+eta)*sqrt(2*prop%sigma(e)/pi/M_wat**3)*rho_bg(e)**2/prop%rho(e)*exp(-4*pi*r_crit**2*prop%sigma(e)/3/K_b/T_bg(e))

      ap(e)=0._8
      sumf=0.
      rp=[geom%xc(e),geom%yc(e),geom%zc(e)]
      sumdefc=0.
      do idx=geom%ef2nb_idx(e),geom%ef2nb_idx(e+1)-1
        anb(idx)=0.
        call get_idx(geom%ef2nb(idx,1),0,enb,lfnb)
        if(lfnb==0) cycle
        fg=geom%ef2nb(idx,2)
        fg_sgn = sgn(fg)
        fg=abs(fg)
        i=3*fg-2
        area=sqrt(geom%aip(i)**2+geom%aip(i+1)**2+geom%aip(i+2)**2)
        norm=fg_sgn*geom%aip(i:i+2)/area
        rip=geom%rip(i:i+2)
        rpnb=[geom%xc(enb),geom%yc(enb),geom%zc(enb)]
        dr = rpnb-rp
        call vec_weight(wt,rip,rp,rpnb)

        ! advection term
        ! inward flux
        f=-fg_sgn*eqn%mip(fg)
        ! upwind bias
        fnb=max(f,0.)
        sumf=sumf+f


        anb(idx)=fnb
        ap(e)=ap(e)+fnb
      enddo

      ap0=prop%rho(e)*geom%vol(e)/dt
      ap(e)=ap(e)+ap0
      b(e)=ap0*eqn%phi0(e)+sumf*eqn%phi(e)+sumdefc

    end do

   ! set boundary conditions
    do ibc=1,size(eqn%bcs)
      do enb=eqn%bcs(ibc)%esec(1),eqn%bcs(ibc)%esec(2)
        call get_idx(abs(geom%mg%fine_lvl%bs(enb)),0,e,lf)
        idx =geom%ef2nb_idx(e)+lf-1
        fg = geom%ef2nb(idx,2)! always outward on boundary
        i=3*fg-2
        area=sqrt(geom%aip(i)**2+geom%aip(i+1)**2+geom%aip(i+2)**2)
        norm=geom%aip(i:i+2)/area
        rip=geom%rip(i:i+2)
        dr=[geom%xc(enb)-geom%xc(e),geom%yc(enb)-geom%yc(e),geom%zc(enb)-geom%zc(e)]
        ds=dot_product(dr,norm)
        select case(trim(eqn%bcs(ibc)%bc_type))
          case('dirichlet')
            f=0.
            d=0!prop%tc(e)*area/ds/prop%cp(e)

            !b(e)=b(e)
          case('zero_flux')
            f=0.
            ! TODO
            !d=prop%tc(e)*area/ds/prop%cp(e)
        end select
        ap(e)=ap(e)+d+f
        anb(idx)=anb(idx)+d+f
      end do
    end do
  end subroutine

! boundary conditions for vfr

    subroutine lid(bc,geom,eqn,prop)
      use mod_util

      class(bc_t) :: bc
      type(geometry_t) :: geom
      class(equation_t) :: eqn
      type(properties_t) :: prop
      integer :: e,enb,lfnb,idx,fg

      bc%bc_type='dirichlet'
      select type(eqn)
      type is(vfr_t)
        do e=bc%esec(1),bc%esec(2)
          call get_idx(abs(geom%mg%fine_lvl%bs(e)),0,enb,lfnb)
          eqn%phi(e)=0.
        end do
      end select

    end subroutine

    subroutine dirichlet0(bc,geom,eqn,prop)
      use mod_util
      class(bc_t) :: bc
      type(geometry_t) :: geom
      class(equation_t) :: eqn
      type(properties_t) :: prop
      integer :: e,enb,lfnb,idx,fg

      bc%bc_type='dirichlet'
      select type(eqn)
      type is(vfr_t)
        do e=bc%esec(1),bc%esec(2)
          call get_idx(abs(geom%mg%fine_lvl%bs(e)),0,enb,lfnb)
          eqn%phi(e)=0.
        end do
      end select

    end subroutine

end module