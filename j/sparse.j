# Compressed sparse columns data structure
type SparseArray2d{T} <: Matrix{T}
    m::Size                # Number of rows
    n::Size                # Number of columns
    colptr::Vector{Size}   # Column i is in colptr[i]:(colptr[i+1]-1)
    rowval::Vector{Size}   # Row values of nonzeros
    nzval::Vector{T}       # Nonzero values
end

size(S::SparseArray2d) = (S.m, S.n)
nnz(S::SparseArray2d) = S.colptr[S.n+1] - 1

function convert{T}(::Type{Array{T}}, S::SparseArray2d{T})
    A = zeros(T, size(S))
    for col = 1 : S.n
        for k = S.colptr[col] : (S.colptr[col+1]-1)
            A[S.rowval[k], col] = S.nzval[k]
        end
    end
    return A
end

full{T}(S::SparseArray2d{T}) = convert(Array{T}, S)

sparse(I,J,V) = sparse(I,J,V,max(I),max(J))
sparse(I,J,V::Number,m,n) = sparse(I,J,V*ones(typeof(V),length(I)),max(I),max(J))

function sparse{T}(I::Vector{Size}, 
                   J::Vector{Size}, 
                   V::Vector{T}, 
                   m::Size, 
                   n::Size)

    (I,p) = sortperm(I)
    J = J[p]
    V = V[p]

    (J,p) = sortperm(J)
    I = I[p]
    V = V[p]

    lastdup = 1
    for k=2:length(I)
        if I[k] == I[lastdup] && J[k] == J[lastdup]
            I[k] = -1
            J[k] = -1
            V[lastdup] += V[k]
        else
            lastdup = k
        end
    end

    select = find(I > 0)
    I = I[select]
    J = J[select]
    V = V[select]

    numnz = length(I)

    w = zeros(Size, n+1)    
    w[1] = 1
    for k=1:numnz; w[J[k] + 1] += 1; end
    colptr = cumsum(w)

    return SparseArray2d(m, n, colptr, I, V)
end

function find{T}(S::SparseArray2d{T})
    numnz = nnz(S)
    I = Array(Size, numnz)
    J = Array(Size, numnz)
    V = Array(T, numnz)

    count = 1
    for col = 1 : S.n
        for k = S.colptr[col] : (S.colptr[col+1]-1)
            if S.nzval[k] != 0
                I[count] = S.rowval[k]
                J[count] = col
                V[count] = S.nzval[k]
                count += 1
            end
        end
    end

    if numnz != count-1
        I = I[1:count]
        J = J[1:count]
        V = V[1:count]
    end

    return (I, J, V)
end

function sprand_rng(m, n, density, rng)
    numnz = int32(m*n*density)
    I = [ randint(1, m) | i=1:numnz ]
    J = [ randint(1, n) | i=1:numnz ]
    V = rng(numnz)
    S = sparse(I, J, V, m, n)
end

sprand(m,n,density) = sprand_rng (m,n,density,rand)
sprandn(m,n,density) = sprand_rng (m,n,density,randn)
#sprandint(m,n,density) = sprand_rng (m,n,density,randint)

speye(n::Size) = ( L = linspace(1,n); sparse(L, L, ones(Int32, n), n, n) )
speye(m::Size, n::Size) = ( x = min(m,n); L = linspace(1,x); sparse(L, L, ones(Int32, x), m, n) )

transpose(S::SparseArray2d) = ( (I,J,V) = find(S); sparse(J, I, V, S.n, S.m) )
ctranspose(S::SparseArray2d) = ( (I,J,V) = find(S); sparse(J, I, conj(V), S.n, S.m) )

function show(S::SparseArray2d)
    println(S.m, "-by-", S.n, " sparse matrix with ", nnz(S), " nonzeros:")
    for col = 1:S.n
        for k = S.colptr[col] : (S.colptr[col+1]-1)
            print("\t[")
            show(S.rowval[k])
            print(",\t", col, "] =\t")
            show(S.nzval[k])
            println()
        end
    end
end

macro sparse_binary_op_sparse_res(op)
    quote
        function ($op){T1,T2}(A::SparseArray2d{T1}, B::SparseArray2d{T2})
            assert(size(A) == size(B))
            (m, n) = size(A)
            
            typeS = promote_type(T1, T2)
            # TODO: Need better method to allocate result
            nnzS = nnz(A) + nnz(B) 
            colptrS = Array(Size, A.n+1)
            rowvalS = Array(Size, nnzS)
            nzvalS = Array(typeS, nnzS)

            zero = convert(typeS, 0)
            
            colptrA = A.colptr
            rowvalA = A.rowval
            nzvalA = A.nzval
            
            colptrB = B.colptr
            rowvalB = B.rowval
            nzvalB = B.nzval
            
            ptrS = 1
            colptrS[1] = 1
            
            for col = 1:n
                ptrA = colptrA[col]
                stopA = colptrA[col+1]
                ptrB = colptrB[col]
                stopB = colptrB[col+1]
                
                while ptrA < stopA && ptrB < stopB
                    rowA = rowvalA[ptrA]
                    rowB = rowvalB[ptrB]
                    if rowA < rowB
                        res = ($op)(nzvalA[ptrA], zero)
                        if res != zero
                            rowvalS[ptrS] = rowA
                            nzvalS[ptrS] = ($op)(nzvalA[ptrA], zero)
                            ptrS += 1
                        end
                        ptrA += 1
                    elseif rowB < rowA
                        res = ($op)(zero, nzvalB[ptrB])
                        if res != zero
                            rowvalS[ptrS] = rowB
                            nzvalS[ptrS] = res
                            ptrS += 1
                        end
                        ptrB += 1
                    else
                        res = ($op)(nzvalA[ptrA], nzvalB[ptrB])
                        if res != zero
                            rowvalS[ptrS] = rowA
                            nzvalS[ptrS] = res
                            ptrS += 1
                        end
                        ptrA += 1
                        ptrB += 1
                    end
                end
                
                while ptrA < stopA
                    res = ($op)(nzvalA[ptrA], zero)
                    if res != zero
                        rowvalS[ptrS] = rowA
                        nzvalS[ptrS] = ($op)(nzvalA[ptrA], zero)
                        ptrS += 1
                    end
                    ptrA += 1
                end
                
                while ptrB < stopB
                    res = ($op)(zero, nzvalB[ptrB])
                    if res != zero
                        rowvalS[ptrS] = rowB
                        nzvalS[ptrS] = res
                        ptrS += 1
                    end
                    ptrB += 1
                end
                
                colptrS[col+1] = ptrS
            end
    
            return SparseArray2d(m, n, colptrS, rowvalS, nzvalS)
        end
    end
end

@sparse_binary_op_sparse_res (+)
@sparse_binary_op_sparse_res (-)
@sparse_binary_op_sparse_res (.*)

(.*)(A::SparseArray2d, x::Number) = SparseArray2d(A.m, A.n, A.colptr, A.rowval, A.nzval .* x)
(.*)(x::Number, A::SparseArray2d) = A .* x
