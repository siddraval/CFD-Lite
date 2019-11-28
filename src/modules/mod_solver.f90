module mod_solver
  use mod_util
  implicit none

    character(len=*), parameter :: oformat = "(5x,A16,x,i5,x,15x,es9.3e2,3x,es9.3e2,3x,es9.3e2)"
 contains
  pure function matinv3(A) result(B)
  implicit none
  real, intent(in) :: A(3,3)   !! Matrix
  real             :: B(3,3)   !! Inverse matrix
  real             :: det,detinv

  det = (  A(1,1)*A(2,2)*A(3,3) - A(1,1)*A(2,3)*A(3,2)&
         - A(1,2)*A(2,1)*A(3,3) + A(1,2)*A(2,3)*A(3,1)&
         + A(1,3)*A(2,1)*A(3,2) - A(1,3)*A(2,2)*A(3,1))

  if(abs(det)>tiny(det)) then
    detinv=1._8/det

    B(1,1) = +detinv * (A(2,2)*A(3,3) - A(2,3)*A(3,2))
    B(2,1) = -detinv * (A(2,1)*A(3,3) - A(2,3)*A(3,1))
    B(3,1) = +detinv * (A(2,1)*A(3,2) - A(2,2)*A(3,1))
    B(1,2) = -detinv * (A(1,2)*A(3,3) - A(1,3)*A(3,2))
    B(2,2) = +detinv * (A(1,1)*A(3,3) - A(1,3)*A(3,1))
    B(3,2) = -detinv * (A(1,1)*A(3,2) - A(1,2)*A(3,1))
    B(1,3) = +detinv * (A(1,2)*A(2,3) - A(1,3)*A(2,2))
    B(2,3) = -detinv * (A(1,1)*A(2,3) - A(1,3)*A(2,1))
    B(3,3) = +detinv * (A(1,1)*A(2,2) - A(1,2)*A(2,1))
  else
    B=0._8
    det=A(1,1)+A(2,2)+A(3,3)
    detinv=1._8/det
    B(1,1)=detinv
    B(2,2)=detinv
    B(3,3)=detinv
  endif
  end function

  subroutine calc_grad(phi,grad,xc,yc,zc,ef2nb_idx,ef2nb,ne,nf,nbf)
    real, dimension(3,ne+nbf) :: grad
    real, dimension(ne+nbf) :: phi
    integer :: ef2nb_idx(ne+1),ef2nb(2*nf-nbf,2)
    integer :: ne,nf,nbf
    integer :: e,idx,enb,lfnb
    real :: ga11,ga12,ga13,ga22,ga23,ga33,A(3,3),B(3,1),C(3,1),A_inv(3,3),dphi,dr(3),wt,xc(ne+nbf),yc(ne+nbf),zc(ne+nbf)

    do e=1,ne
      A=0.
      grad(:,e)=0.
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        dr = [xc(enb)-xc(e),yc(enb)-yc(e),zc(enb)-zc(e)]

        wt = 1./sum(dr**2)

        dphi=phi(enb)-phi(e)
        grad(:,e)=grad(:,e)+wt*dphi*dr

        A(1,1)=A(1,1)+wt*dr(1)*dr(1)
        A(1,2)=A(1,2)+wt*dr(1)*dr(2)
        A(1,3)=A(1,3)+wt*dr(1)*dr(3)
        A(2,2)=A(2,2)+wt*dr(2)*dr(2)
        A(2,3)=A(2,3)+wt*dr(2)*dr(3)
        A(3,3)=A(3,3)+wt*dr(3)*dr(3)

      end do

      A(2,1)=A(1,2)
      A(3,1)=A(1,3)
      A(3,2)=A(2,3)

      A_inv = matinv3(A)

      B(:,1)=grad(:,e)
      C=matmul(A_inv,B)
      grad(:,e)=C(:,1)

    enddo

  end subroutine

  subroutine internal_extrapolation_grad(phi,e,grad,xc,yc,zc,ef2nb_idx,ef2nb,ne,nf,nbf)
    real, dimension(3) :: grad
    real, dimension(ne+nbf) :: phi
    integer :: ef2nb_idx(ne+1),ef2nb(2*nf-nbf,2)
    integer :: ne,nf,nbf
    integer :: e,idx,enb,lfnb
    real :: ga11,ga12,ga13,ga22,ga23,ga33,A(3,3),B(3,1),C(3,1),A_inv(3,3),dphi,dr(3),wt,xc(ne+nbf),yc(ne+nbf),zc(ne+nbf)

      grad=0.
      A=0.
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        if(lfnb==0) cycle
        dr = [xc(enb)-xc(e),yc(enb)-yc(e),zc(enb)-zc(e)]

        wt = 1./sum(dr**2)

        dphi=phi(enb)-phi(e)
        grad=grad+wt*dphi*dr

        A(1,1)=A(1,1)+wt*dr(1)*dr(1)
        A(1,2)=A(1,2)+wt*dr(1)*dr(2)
        A(1,3)=A(1,3)+wt*dr(1)*dr(3)
        A(2,2)=A(2,2)+wt*dr(2)*dr(2)
        A(2,3)=A(2,3)+wt*dr(2)*dr(3)
        A(3,3)=A(3,3)+wt*dr(3)*dr(3)

      end do

      A(2,1)=A(1,2)
      A(3,1)=A(1,3)
      A(3,2)=A(2,3)

      A_inv = matinv3(A)

      B(:,1)=grad
      C=matmul(A_inv,B)
      grad=C(:,1)

  end subroutine

  subroutine solve_gs(cname,phi,ap,anb,b,ef2nb_idx,ef2nb,ne,nf,nbf,nit)
    implicit none
    character(len=*) :: cname
    character(len=16) :: name
    real, dimension(ne+nbf) :: phi
    real, dimension(ne) :: ap,b
    real, dimension(2*nf-nbf) :: anb
    integer :: ef2nb_idx(ne+1),ef2nb(2*nf-nbf,2)
    integer :: ne,nf,nbf,nit,it
    integer :: e,idx,enb,lfnb
    real :: sumnb,res_i,res_f,res_target,res_max,r
    real :: sor

    sor=1.
    if(cname(1:2)=='pc') sor=1.02

    res_i=0.! initial residual
    do e=1,ne
      sumnb=b(e)
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        sumnb=sumnb+anb(idx)*phi(enb)
      end do
      r=sumnb-ap(e)*phi(e)
      res_i=res_i+r**2
    end do
    res_i=sqrt(res_i/ne)

  it=0
  res_f=res_i
  res_target=res_i/10.! reduce residual 1 order of magnitude
  if(cname(1:2)=='pc') res_target=res_i/10.
  do while(it<nit .and. res_f>res_target)
    it=it+1
    ! forward sweep
    do e=1,ne
      sumnb=b(e)
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        sumnb=sumnb+anb(idx)*phi(enb)
      end do
      phi(e)=(sumnb+(sor-1.)*ap(e)*phi(e))/ap(e)/sor
    end do

    ! backward sweep
    do e=ne,1,-1
      sumnb=b(e)
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        sumnb=sumnb+anb(idx)*phi(enb)
      end do
      phi(e)=(sumnb+(sor-1.)*ap(e)*phi(e))/ap(e)/sor
    end do

    res_max=0.
    res_f=0.! final residual
    do e=1,ne
      sumnb=b(e)
      do idx=ef2nb_idx(e),ef2nb_idx(e+1)-1
        call get_idx(ef2nb(idx,1),0,enb,lfnb)
        sumnb=sumnb+anb(idx)*phi(enb)
      end do
      r=abs(sumnb-ap(e)*phi(e))
      res_max=max(r,res_max)
      res_f=res_f+r**2
    end do
    res_f=sqrt(res_f/ne)
  enddo

  name=trim(cname)
  write(*,oformat) name,it,res_i,res_f,res_max

  end subroutine
end module