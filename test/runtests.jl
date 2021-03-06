using ParameterizedFunctions, DiffEqBase
using Base.Test

using SpecialFunctions

### ODE Macros

println("Build some examples")
f_t = @ode_def_nohes SymCheck begin # Checks for error due to symbol on 1
  dx = x
  dy = -c*y + d*x*y*t^2
end a=>1.5 b=>1 c=3 d=1

@test has_syms(f_t)

f_t2 = @ode_def_noinvjac SymCheck2 begin # Checks for error due to symbol on 1
  dx = 1
  dy = -c*y + d*x*y*t^2
end a=>1.5 b=>1 c=3 d=1

f_t3 = @ode_def_noinvjac ExprCheck begin # Checks for error due to symbol on 1
  dx = a*x - b*x*y
  dy = -c*y + d*x*y
end a=>1.5 b=>2.0 c=t*x d=2pi # Change to π after unicode fix

f = @ode_def_noinvhes LotkaVolterra begin
  dx = a*x - b*x*y
  dy = -c*y + d*x*y
end a=>1.5 b=>1 c=>3 d=1

f_2 = @ode_def_nohes LotkaVolterra3 begin
  dx = a*x - b^2*x*y
  dy = -c*y + d*x*y
end a=>1.5 b=>1 c=>3 d=1

mutable struct  LotkaVolterra2 <: AbstractParameterizedFunction{true}
         a::Float64
         b::Int64
end
(p::LotkaVolterra2)(t,u,du) = begin
         du[1] = p.a * u[1] - p.b * u[1]*u[2]
         du[2] = -3 * u[2] + u[1]*u[2]
end

println("Test Values")
@test param_values(f_t) == Real[1.5,1]
@test param_values(f) == Real[1.5,1,3]
@test num_params(f_t) == 2
@test num_params(f) == 3
t = 1.0
u = [2.0,3.0]
du = zeros(2)
grad = similar(du)
J = zeros(2,2)
iJ= zeros(2,2)
iW= zeros(2,2)
f(t,u,du)
@test du == [-3.0,-3.0]
@test du == f(t,u)
f_t(t,u,du)
@test du == [2.0,-3.0]
f_t2(t,u,du)
@test du == [1.0,-3.0]

println("Test t-gradient")
f(Val{:tgrad},t,u,grad)
@test grad == zeros(2)
f_t(Val{:tgrad},t,u,grad)
@test grad == [0.0;12.0]

println("Test Explicit Parameter Functions")
f(Val{:a},t,u,2.0,du)
@test du == [-2.0,-3.0]
f(Val{:deriv},Val{:a},t,u,2.0,du)
@test du == [2.0,0.0]
f(t,u,[2.0;2.5;3.0],du)
@test du == [-11.0;-3.0]

println("Test Jacobians")
f(Val{:jac},t,u,J)
f(Val{:invjac},t,u,iJ)
@test J  == [-1.5 -2.0
             3.0 -1.0]
@test f(Val{:jac}, t, u) == [-1.5 -2.0; 3.0 -1.0]
@test minimum(iJ - inv(J) .< 1e-10)

println("Test Inv Rosenbrock-W")
f(Val{:invW},t,u,2.0,iW)
@test minimum(iW - inv(I - 2*J) .< 1e-10)

f(Val{:invW_t},t,u,2.0,iW)
@test minimum(iW - inv(I/2 - J) .< 1e-10)

println("Parameter Jacobians")
pJ = Matrix{Float64}(2,3)
f(Val{:paramjac},t,u,[2.0;2.5;3.0],pJ)
@test pJ == [2.0 -6.0 0
             0 0 -3.0]

#=
println("Test Hessians")
H = J
iH = iJ
f(Val{:hes},t,u,H)
@test_throws MethodError f(Val{:invhes},t,u,iH)
@test J  == [0.0 0.0
             0.0 0.0]
=#

println("Test using new parameters")
g = LotkaVolterra(a=1.0,b=2.0)
@test g.b == 2.0
@test g.a == 1.0
@test g.a * u[1] - g.b * u[1]*u[2] == -10.0
g(t,u,du)
@test du == [-10.0,-3.0]
@test du == g(t,u)
h = LotkaVolterra2(1.0,2.0)
h(t,u,du)
@test du == [-10.0,-3.0]

@code_llvm has_jac(f)

println("Test booleans")
@test has_jac(f) == true
@test has_invjac(f) == true
@test has_hes(f) == false
@test has_invhes(f) == false
@test has_paramderiv(f) == true
@test has_paramjac(f) == true

@code_llvm has_paramjac(f)

println("Test difficult differentiable")
NJ = @ode_def_nohes DiffDiff begin
  dx = a*x - b*x*y
  dy = -c*y + erf(x*y/d)
end a=>1.5 b=>1 c=3 d=4
NJ(t,u,du)
@test du == [-3.0;-3*3.0 + erf(2.0*3.0/4)]
@test du == NJ(t,u)
# NJ(Val{:jac},t,u,J) # Currently gives E not defined, will be fixed by the next SymEgine

test_fail(x,y,d) = erf(x*y/d)
println("Test non-differentiable")
NJ = @ode_def NoJacTest begin
  dx = a*x - μ*x*y
  dy = -c*y + test_fail(x,y,d)
end a=>1.5 μ=>1 c=3 d=4
NJ(t,u,du)
@test du == [-3.0;-3*3.0 + erf(2.0*3.0/4)]
@test du == NJ(t,u)
@test_throws MethodError NJ(Val{:jac},t,u,iJ)
# NJ(Val{:jac},t,u,J) # Currently gives E not defined, will be fixed by the next SymEgine
### FEM Macros

println("Test FEM")
f = @fem_def (t,x) TestType begin
  du = exp.(-t-5*(1-2x+2x.^2 - 2y +2y.^2)).*(-161 + a*(x - x.^2 + y - y.^2))
end a=400
g = (t,x) -> exp.(-t-5*(1-2x[:,1]+2x[:,1].^2 - 2x[:,2] +2x[:,2].^2)).*(-161 + 400*(x[:,1] - x[:,1].^2 + x[:,2] - x[:,2].^2))
x = rand(4,2)

h = (t,x,u)  -> [1-.5*2.0*u[:,1]   -1-u[:,2]]

l = @fem_def (t,x,u) TestType2 begin
  du = 1-α*β*u
  dv = -1-v
end α=>0.5 β=2.0

@test f(1.0,x) == g(1.0,x)
@test h(1.0,x,x) == l(1.0,x,x)

@testset "Parameters Interface Test" begin include("parameters_interface_test.jl") end

println("Make sure all of the problems in the problem library build")
using DiffEqProblemLibrary
