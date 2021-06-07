module IntegrationTests

using Gridap
using FillArrays
using Gridap.Geometry
using ExploringGridapHybridization

u(x) = VectorValue(1+x[1],1+x[2])
Gridap.divergence(::typeof(u)) = (x) -> 2
p(x) = -3.14
∇p(x) = VectorValue(0,0)
Gridap.∇(::typeof(p)) = ∇p
f(x) = u(x) + ∇p(x)
# Normal component of u(x) on Neumann boundary
function g(x)
  tol=1.0e-14
  if (abs(x[2])<tol)
    return -x[2] #-x[1]-x[2]
  elseif (abs(x[2]-1.0)<tol)
    return x[2] # x[1]+x[2]
  end
  Gridap.Helpers.@check false
end


function solve_darcy_rt_hdiv()
  domain = (0,1,0,1)
  partition = (1,1)
  order = 0
  model = CartesianDiscreteModel(domain,partition)
  V = FESpace(model,
              ReferenceFE(raviart_thomas,Float64,order),
              conformity=:Hdiv)#,dirichlet_tags=[5,6,7,8])
  Q = FESpace(model,ReferenceFE(lagrangian,Float64,order); conformity=:L2)
  U = TrialFESpace(V,u)
  P = TrialFESpace(Q)
  Y = MultiFieldFESpace([V, Q])
  X = MultiFieldFESpace([U, P])
  trian = Triangulation(model)
  degree = 2*(order+1)
  dΩ = Measure(trian,degree)
  neumanntags = [5,6,7,8]
  btrian = BoundaryTriangulation(model,tags=neumanntags)
  dΓ = Measure(btrian,degree)
  nb = get_normal_vector(btrian)
  a((u, p),(v, q)) = ∫( u⋅v - (∇⋅v)*p + q*(∇⋅u) )*dΩ
  b(( v, q)) = ∫( v⋅f + q*(∇⋅u))*dΩ - ∫((v⋅nb)*p )*dΓ
  op = AffineFEOperator(a,b,X,Y)
  println(op.op.matrix)
  println(op.op.vector)
  xh = solve(op)
end


# Geometry part
D=2
domain  = (0,1,0,1)
cells   = (1,1)
model   = CartesianDiscreteModel(domain,cells)
model_Γ = BoundaryDiscreteModel(Polytope{D-1},model,collect(1:num_facets(model)))

# Functional part
# To investigate what is needed to have an inf-sup stable triplet
# for the RT-H method
order  = 0
reffeᵤ = ReferenceFE(raviart_thomas,Float64,order)
reffeₚ = ReferenceFE(lagrangian,Float64,order)
reffeₗ = ReferenceFE(lagrangian,Float64,order)

# Define test FESpaces
V = TestFESpace(model  , reffeᵤ; conformity=:L2)
Q = TestFESpace(model  , reffeₚ; conformity=:L2)
M = TestFESpace(model_Γ, reffeₗ; conformity=:L2)
Y = MultiFieldFESpace([V,Q,M])

# Create trial spaces
U = TrialFESpace(V)
P = TrialFESpace(Q)
L = TrialFESpace(M)
X = MultiFieldFESpace([U, P, L])

yh = get_fe_basis(Y)
vh,qh,mh = yh

xh = get_trial_fe_basis(X)
uh,ph,lh = xh

mhscal=get_fe_basis(M)
lhscal=get_fe_basis(L)

trian = Triangulation(model)
degree = 2*(order+1)
dΩ = Measure(trian,degree)

# neumanntags  = [5,6]
# # TO-DO: neumanntrian = Triangulation(model_Γ,tags=neumanntags) this causes
# # dcvΓ=∫(mh*g)*dΓ to fail in change_domain ...
# neumanntrian = BoundaryTriangulation(model,tags=neumanntags)
# degree = 2*(order+1)
# dΓn = Measure(neumanntrian,degree)

dirichlettags  = [5,6,7,8]
dirichlettrian = BoundaryTriangulation(model,tags=dirichlettags)
dΓd = Measure(dirichlettrian,degree)

dcmΩ=∫( vh⋅uh - (∇⋅vh)*ph + qh*(∇⋅uh) )*dΩ
dvmΓd=∫(mhscal*lhscal)*dΓd
dcvΩ=∫( vh⋅f + qh*(∇⋅u))*dΩ
#dcvΓn=∫(mhscal*g)*dΓn
dcvΓd=∫(mhscal*p)*dΓd

data_mΩ=Gridap.CellData.get_contribution(dcmΩ,dΩ.quad.trian)
data_mΓd=Gridap.CellData.get_contribution(dvmΓd,dΓd.quad.trian)
data_vΩ=Gridap.CellData.get_contribution(dcvΩ,dΩ.quad.trian)
#data_vΓn=Gridap.CellData.get_contribution(dcvΓn,dΓn.quad.trian)
data_vΓd=Gridap.CellData.get_contribution(dcvΓd,dΓd.quad.trian)

∂T     = CellBoundary(model)
x,w    = quadrature_evaluation_points_and_weights(∂T,2)


#∫( mh*(uh⋅n) )*dK
@time uh_∂T = restrict_to_cell_boundary(∂T,uh)
@time mh_∂T = restrict_to_cell_boundary(∂T,mh)
@time mh_mult_uh_cdot_n=integrate_mh_mult_uh_cdot_n_low_level(∂T,mh_∂T,uh_∂T,x,w)

#∫( (vh⋅n)*lh )*dK
@time vh_∂T = restrict_to_cell_boundary(∂T,vh)
@time lh_∂T = restrict_to_cell_boundary(∂T,lh)
@time vh_cdot_n_mult_lh=integrate_vh_cdot_n_mult_lh_low_level(∂T,vh_∂T,lh_∂T,x,w)

cmat=lazy_map(Broadcasting(+),
              lazy_map(Broadcasting(+),vh_cdot_n_mult_lh,mh_mult_uh_cdot_n),
              data_mΩ)

cvec=data_vΩ

# cell=2
# A11=vcat(hcat(cmat[cell][1,1],cmat[cell][1,2]),hcat(cmat[cell][2,1],0.0))
# A12=vcat(cmat[cell][1,3],zeros(1,4))
# A21=hcat(cmat[cell][3,1],zeros(4))
# S22=-A21*inv(A11)*A12
# b1=vcat(cvec[cell][1],cvec[cell][2])
# y2=-A21*inv(A11)*b1

k=StaticCondensationMap([1,2],[3])
cmat_cvec_condensed=lazy_map(k,cmat,cvec)

#fdofsn=get_cell_dof_ids(M,neumanntrian)
fdofsd=get_cell_dof_ids(M,dirichlettrian)

fdofscb=restrict_facet_dof_ids_to_cell_boundary(∂T,get_cell_dof_ids(M))
assem = SparseMatrixAssembler(M,L)
#@time A,b=assemble_matrix_and_vector(assem,(([cmat_cvec_condensed], [fdofscb], [fdofscb]),
#                                      ([data_mΓd],[fdofsd],[fdofsd]),
#                                      ([data_vΓn,data_vΓd],[fdofsn,fdofsd])))
@time A,b=assemble_matrix_and_vector(assem,(([cmat_cvec_condensed], [fdofscb], [fdofscb]),
                                      ([data_mΓd],[fdofsd],[fdofsd]),
                                      ([data_vΓd],[fdofsd])))
x     = A\b
lh    = FEFunction(L,x)

k=BackwardStaticCondensationMap([1,2],[3])
lhₖ= lazy_map(Gridap.Fields.Broadcasting(Gridap.Fields.PosNegReindex(
                      Gridap.FESpaces.get_free_dof_values(lh),lh.dirichlet_values)),
                      fdofscb)
uhphlhₖ=lazy_map(k,cmat,cvec,lhₖ)

tol=1.0e-12

cell=1
A11=vcat(hcat(cmat[cell][1,1],cmat[cell][1,2]),hcat(cmat[cell][2,1],0.0))
A12=vcat(cmat[cell][1,3],zeros(1,4))
A21=hcat(cmat[cell][3,1],zeros(4))
Am=vcat(hcat(A11,A12),hcat(A21,zeros(4,4)))
Am[6,6]=1.0
Am[7,7]=1.0
Am[8,8]=1.0
Am[9,9]=1.0

Sm=Am[6:9,6:9]-Am[6:9,1:5]*inv(Am[1:5,1:5])*Am[1:5,6:9]
ym=vcat(data_vΓd...)-A21*inv(Am[1:5,1:5])*vcat(cvec[1][1],cvec[1][2])
xm=Sm\ym
@assert norm(xm-x) < tol
bm=vcat(cvec[1][1],cvec[1][2],data_vΓd...)
Am\bm

lhₑ=lazy_map(Gridap.Fields.BlockMap(3,3),ExploringGridapHybridization.convert_cell_wise_dofs_array_to_facet_dofs_array(∂T,
      lhₖ,get_cell_dof_ids(M)))

assem = SparseMatrixAssembler(Y,X)
lhₑ_dofs=get_cell_dof_ids(X,Triangulation(model_Γ))

uhph_dofs=get_cell_dof_ids(X,Triangulation(model))
uhph_dofs = lazy_map(Gridap.Fields.BlockMap(2,[1,2]),uhph_dofs.args[1],uhph_dofs.args[2])

uh=lazy_map(x->x[1],uhphlhₖ)
ph=lazy_map(x->x[2],uhphlhₖ)
uhphₖ=lazy_map(Gridap.Fields.BlockMap(2,[1,2]),uh,ph)

free_dof_values=assemble_vector(assem,([lhₑ,uhphₖ],[lhₑ_dofs,uhph_dofs]))
xh=FEFunction(X,free_dof_values)

# cell=1
# A11=vcat(hcat(cmat[cell][1,1],cmat[cell][1,2]),hcat(cmat[cell][2,1],0.0))
# A12=vcat(cmat[cell][1,3],zeros(1,4))
# A21=hcat(cmat[cell][3,1],zeros(4))
# b1=vcat(cvec[cell][1],cvec[cell][2])
# x2=lhₖ[cell]
# x1=inv(A11)*(b1-A12*x2)



end # module
