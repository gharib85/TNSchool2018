using LinearAlgebra, TensorOperations, KrylovKit

safesign(x::Number) = iszero(x) ? one(x) : sign(x)
"""
    qrpos(A)

Returns a QR decomposition, i.e. an isometric `Q` and upper triangular `R` matrix, where `R`
is guaranteed to have positive diagonal elements.
"""
qrpos(A) = qrpos!(copy(A))
function qrpos!(A)
    F = qr!(A)
    Q = Matrix(F.Q)
    R = F.R
    phases = safesign.(diag(R))
    rmul!(Q, Diagonal(phases))
    lmul!(Diagonal(conj!(phases)), R)
    return Q, R
end

"""
    lqpos(A)

Returns a LQ decomposition, i.e. a lower triangular `L` and isometric `Q` matrix, where `L`
is guaranteed to have positive diagonal elements.
"""
lqpos(A) = lqpos!(copy(A))
function lqpos!(A)
    F = qr!(Matrix(A'))
    Q = Matrix(Matrix(F.Q)')
    L = Matrix(F.R')
    phases = safesign.(diag(L))
    lmul!(Diagonal(phases), Q)
    rmul!(L, Diagonal(conj!(phases)))
    return L, Q
end

"""
    leftorth(A, [C]; kwargs...)

Given an MPS tensor `A`, return a left-canonical MPS tensor `AL`, a gauge transform `C` and
a scalar factor `λ` such that ``λ AL^s C = C A^s``, where an initial guess for `C` can be
provided.
"""
function leftorth(A, C = Matrix{eltype(A)}(I, size(A,1), size(A,1)); tol = 1e-12, maxiter = 100, kwargs...)
    λ2s, ρs, info = eigsolve(C'*C, 1, :LM; ishermitian = false, tol = tol, maxiter = 1, kwargs...) do ρ
        @tensor ρE[a,b] := ρ[a',b']*A[b',s,b]*conj(A[a',s,a])
        return ρE
    end
    ρ = ρs[1] + ρs[1]'
    ρ ./= tr(ρ)
    # C = cholesky!(ρ).U
    # If ρ is not exactly positive definite, cholesky will fail
    F = svd!(ρ)
    C = lmul!(Diagonal(sqrt.(F.S)), F.Vt)
    _, C = qrpos!(C)

    D, d, = size(A)
    Q, R = qrpos!(reshape(C*reshape(A, D, d*D), D*d, D))
    AL = reshape(Q, D, d, D)
    λ = norm(R)
    rmul!(R, 1/λ)
    numiter = 1
    while norm(C-R) > tol && numiter < maxiter
        # C = R
        λs, Cs, info = eigsolve(R, 1, :LM; ishermitian = false, tol = tol, maxiter = 1, kwargs...) do X
            @tensor Y[a,b] := X[a',b']*A[b',s,b]*conj(AL[a',s,a])
            return Y
        end
        _, C = qrpos!(Cs[1])
        # The previous lines can speed up the process when C is still very far from the correct
        # gauge transform, it finds an improved value of C by finding the fixed point of a
        # 'mixed' transfer matrix composed of `A` and `AL`, even though `AL` is also still not
        # entirely correct. Therefore, we restrict the number of iterations to be 1 and don't
        # check for convergence
        Q, R = qrpos!(reshape(C*reshape(A, D, d*D), D*d, D))
        AL = reshape(Q, D, d, D)
        λ = norm(R)
        rmul!(R, 1/λ)
        numiter += 1
    end
    C = R
    return AL, C, λ
end

"""
    rightorth(A, [C]; kwargs...)

Given an MPS tensor `A`, return a gauge transform C, a right-canonical MPS tensor `AR`, and
a scalar factor `λ` such that ``λ C AR^s = A^s C``, where an initial guess for `C` can be
provided.
"""
function rightorth(A, C = Matrix{eltype(A)}(I, size(A,1), size(A,1)); tol = 1e-12, kwargs...)
    # TODO
end

"""
    applyH1(AC, FL, FR, M)

Apply the effective Hamiltonian on the center tensor `AC`, by contracting with the left and right
environment `FL` and `FR` and the MPO tensor `M`
"""
function applyH1(AC, FL, FR, M)
    # TODO
end

"""
    applyH0(C, FL, FR)

Apply the effective Hamiltonian on the bond matrix C, by contracting with the left and right
environment `FL` and `FR`
"""
function applyH0(C, FL, FR)
    # TODO
end

"""
    leftenv(A, M, FL; kwargs)

Compute the left environment tensor for MPS A and MPO M, by finding the left fixed point
of A - M - conj(A) contracted along the physical dimension.
"""
function leftenv(A, M, FL = randn(eltype(A), size(A,1), size(M,1), size(A,1)); kwargs...)
    λs, FLs, info = eigsolve(FL, 1, :LM; ishermitian = false, kwargs...) do FL
        # TODO
    end
    return FLs[1], real(λs[1]), info
end
"""
    rightenv(A, M, FR; kwargs...)

Compute the right environment tensor for MPS A and MPO M, by finding the right fixed point
of A - M - conj(A) contracted along the physical dimension.
"""
function rightenv(A, M, FR = randn(eltype(A), size(A,1), size(M,1), size(A,1)); kwargs...)
    λs, FRs, info = eigsolve(FR, 1, :LM; ishermitian = false, kwargs...) do FR
        # TODO
    end
    return FRs[1], real(λs[1]), info
end
function vumps(A, M; verbose = true, tol = 1e-6, kwargs...)
    AL, = leftorth(A)
    C, AR = rightorth(AL)

    FL, λL = leftenv(AL, M; kwargs...)
    FR, λR = rightenv(AR, M; kwargs...)

    verbose && println("Starting point has λ ≈ $λL ≈ $λR")

    λ, AL, C, AR, = vumpsstep(AL, C, AR, M, FL, FR; tol = tol/10)
    AL, C, = leftorth(AR, C; tol = tol/10, kwargs...) # regauge MPS: not really necessary
    FL, λL = leftenv(AL, M, FL; tol = tol/10, kwargs...)
    FR, λR = rightenv(AR, M, FR; tol = tol/10, kwargs...)
    FR ./= @tensor scalar(FL[c,b,a]*C[a,a']*conj(C[c,c'])*FR[a',b,c']) # normalize FL and FR: not really necessary

    # Convergence measure: norm of the projection of the residual onto the tangent space
    @tensor AC[a,s,b] := AL[a,s,b']*C[b',b]
    MAC = applyH1(AC, FL, FR, M)
    @tensor MAC[a,s,b] -= AL[a,s,b']*(conj(AL[a',s',b'])*MAC[a',s',b])
    err = norm(MAC)
    i = 1
    verbose && println("Step $i: λ ≈ $λ ≈ $λL ≈ $λR, err ≈ $err")
    while err > tol
        λ, AL, C, AR, = vumpsstep(AL, C, AR, M, FL, FR; tol = tol/10, kwargs...)
        AL, C, = leftorth(AR, C; tol = tol/10, kwargs...) # regauge MPS: not really necessary
        FL, λL = leftenv(AL, M, FL; tol = tol/10, kwargs...)
        FR, λR = rightenv(AR, M, FR; tol = tol/10, kwargs...)
        FR ./= @tensor scalar(FL[c,b,a]*C[a,a']*conj(C[c,c'])*FR[a',b,c']) # normalize FL and FR: not really necessary

        # Convergence measure: norm of the projection of the residual onto the tangent space
        @tensor AC[a,s,b] := AL[a,s,b']*C[b',b]
        MAC = applyH1(AC, FL, FR, M)
        @tensor MAC[a,s,b] -= AL[a,s,b']*(conj(AL[a',s',b'])*MAC[a',s',b])
        err = norm(MAC)
        i += 1
        verbose && println("Step $i: λ ≈ $λ ≈ $λL ≈ $λR, err ≈ $err")
    end
    return λ, AL, C, AR, FL, FR
end

"""
    function vumpsstep(AL, C, AR, FL, FR; kwargs...)

Perform one step of the VUMPS algorithm
"""
function vumpsstep(AL, C, AR, M, FL, FR; kwargs...)
    D, d, = size(AL)
    @tensor AC[a,s,b] := AL[a,s,b']*C[b',b]
    μ1s, ACs, info1 = eigsolve(x->applyH1(x, FL, FR, M), AC, 1, :LM; ishermitian = false, maxiter = 1, kwargs...)
    μ0s, Cs, info0 = eigsolve(x->applyH0(x, FL, FR), C, 1; ishermitian = false, maxiter = 1, kwargs...)
    λ = real(μ1s[1]/μ0s[1])
    AC = ACs[1]
    C = Cs[1]

    # Obtain a new guess for AL and AR from the updated AC and C
    # TODO
end
