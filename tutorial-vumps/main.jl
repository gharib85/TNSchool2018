using Revise
Revise.includet("mps.jl")

function statmechmpo(β, h, D)
    M = zeros(D,D,D,D)
    for i = 1:D
        M[i,i,i,i] = 1
    end
    X = zeros(D,D)
    for j = 1:D, i = 1:D
        X[i,j] = exp(-β*h(i,j))
    end
    Xsq = sqrt(X)
    @tensor M1[a,b,c,d] := M[a',b',c',d']*Xsq[c',c]*Xsq[d',d]*Xsq[a,a']*Xsq[b,b']

    # For computing energy: M2 is a tensor across 2 nearest neighbor sites in the lattice, whose
    # expectation value in the converged fixed point of the transfer matrix represents the energy
    Y = zeros(D,D)
    for j = 1:D, i = 1:D
        Y[i,j] = h(i,j)*exp(-β*h(i,j))
    end
    @tensor M2[a,b1,b2,c,d2,d1] := M[a',b1',c1,d1']*Xsq[a,a']*Xsq[b1,b1']*Xsq[d1',d1]* Y[c1,c2]*
                                    M[c2,b2',c',d2']*Xsq[b2,b2']*Xsq[d2',d2]*Xsq[c',c]

    return M1, M2
end

classicalisingmpo(β; J = 1.0, h = 0.) = statmechmpo(β, (s1,s2)->-J*(-1)^(s1!=s2) - h/2*(s1==1 + s2==1), 2)

βc = log(1+sqrt(2))/2
β = 0.95*βc
M, M2 = classicalisingmpo(β)
D = 50
A = randn(D, 2, D) + im*randn(D, 2, D)
λ, AL, C, AR, FL, FR = vumps(A, M; tol = 1e-10)


# Compute energy:
#----------------
# Strategy 1:
# Compute energy by contracting M2 with two mps tensors in ket and bra, and the boundaries FL and FR.
# Make sure everything is normalized by dividing through the proper contribution of the partition function
# TODO

# Strategy 2:
# Compute energy using thermodynamic relations: Z = λ^N, i.e. λ is the partition function per site
# E = - d log(Z) / d β => energy (density) = - d log(λ) / d β
# where derivatives are evaluated using finite differences
# TODO

# also compute free energy and entropy
# TODO
