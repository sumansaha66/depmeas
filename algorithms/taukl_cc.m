function [ tau ] = taukl_cc( U, V, autoDetectHybrid, isHybrid, continuousRvIndicator )
%TAUKL - computes a rescaled version of Kendall's tau that preserves
%         the definition of Kendall's tau, but assures that in the 
%         scenario of perfect concordance or discordance for discrete
%         or hybrid datatypes, taucj achieves +/- 1 respectively
% Inputs:
%  U - first variable input.
%  V - second variable input.
%  autoDetectHybrid - if 1, we attempt to automatically determine if the
%                     data is hybrid or not, if 0, then we use the value 
%                     specified by isHybrid
%  isHybrid - if 1, and autoDetectHybrid=0, then we assume data is hybrid
%             if 0, and autoDetectHybrid=0, then we assume data is discrete
%                   and/or continuous
%             if autoDetectHybrid=1, then this input doesn't matter
%  continuousRvIndicator - if 1, and autoDetectHybrid=0, then this indicates that U is continuous & V is discrete
%                        - if 0, and autoDetectHybrid=0, then this indicates that U is continuous & V is discrete
%             if autoDetectHybrid=1, then this input doesn't matter
% Outputs:
%  tau - the rescaled version of Kendall's tau
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% NOTE!!
%  THE CC VERSION REQUIRES U & V to be sorted lexicograpically by U!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

len = length(U);

% compute the numerator the tau_hat
% K = double(ktau_numer(U,V));  % call the C function

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% some gymanstics for Matlab Coder
coder.extrinsic('ktau_numer'); 
numer_val = ktau_numer(U,V);
K = 0;  % see: https://www.mathworks.com/help/simulink/ug/calling-matlab-functions.html#bq1h2z9-47
K = double(numer_val);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if(K==0)
    tau = 0;
    return;
end

% compute the denominator ... compute the # of unique values of U and V and
% how many times each of those unique values occur
[uniqueU, uniqueUCounts] = uniqueSorted(U);
[uniqueV, uniqueVCounts] = uniqueSorted(sort(V));

if((length(uniqueU) >= len/2) && (length(uniqueV) >= len/2))
    % means we can reasonably assume that we have continuous data
    % for data-sizes >=50
    tau = K/(len*(len-1)/2);
    return;
end

u = 0;
k = 2;
for ii=1:length(uniqueU)
    n = uniqueUCounts(ii);
    if(k<=n)
        addVal = nchoosek(n,k);
    else
        addVal = 0;
    end
    u = u + addVal;
end
v = 0;
for ii=1:length(uniqueV)
    n = uniqueVCounts(ii);
    if(k<=n)
        addVal = nchoosek(n,k);
    else
        addVal = 0;
    end
    v = v + addVal;
end

if(autoDetectHybrid)
    uuCloseToZero = closeToZero(u, len);
    vvCloseToZero = closeToZero(v, len);
    if( (uuCloseToZero && v>0) || (u>0 && vvCloseToZero) )
        isHybrid = 1;
        if(uuCloseToZero)
            continuousRvIndicator = 0;
        else
            continuousRvIndicator = 1;
        end
    end
end
if( isHybrid )
    % special case of hybrid data    
    numOverlapPtsVec = countOverlaps(U, V, continuousRvIndicator);
    correctionFactor = correctionFactor4(numOverlapPtsVec);
    t = max(u,v)-correctionFactor;
    tau = K/( sqrt(nchoosek(len,2)-t)*sqrt(nchoosek(len,2)-t) );
else
    % case of either all continuous or all discrete data
    tau = K/( sqrt(nchoosek(len,2)-u)*sqrt(nchoosek(len,2)-v) );
end

end

function [cf] = correctionFactor4(numOverlapPtsVec)
    meanVal = floor(mean(numOverlapPtsVec));
    if(meanVal<2)
        cf = 0;
    else
        cf = nchoosek(meanVal,2)*length(numOverlapPtsVec);
    end
end

function [out] = closeToZero(in, len)
out = 1;
thresh = 0.02;      % if we are > 2% of length in terms of combinations;
lenFloor = floor(len*thresh);

if(lenFloor>=2)
    cmpVal = nchoosek(lenFloor,2);
else
    cmpVal = 0;
end

if(in>cmpVal)
    out = 0;
end

end

function [numOverlapPtsVec] = countOverlaps(U, V, continuousRvIndicator)
% this function is only called for hybrid data, attempts to correct for
% overestimation of the number of ties in hybrid data

M = length(U);

if(continuousRvIndicator==0)
    % U is the continuous RV
    continuousOutcomes = U;
    discreteOutcomes = V;
    % get the number of unique discrete outcomes
    uniqueDiscreteOutcomes = unique(V);
else
    % V is the continuous RV
    continuousOutcomes = V;
    discreteOutcomes = U;
    % get the number of unique discrete outcomes
    uniqueDiscreteOutcomes = unique(U);
end
uniqueDiscreteOutcomes = sort(uniqueDiscreteOutcomes);  % probably already comes sorted?

if(length(uniqueDiscreteOutcomes)==1)
    numOverlapPtsVec = M-1;  % why -1?
else
    % for each unique outcome .. count the overlapping elements.
    numOverlapPtsVec = zeros(1,length(uniqueDiscreteOutcomes)-1);
    for discreteOutcomesIdx=1:length(uniqueDiscreteOutcomes)-1
        % find the min/max values of the continuous values for this idx and the
        % next
        I = discreteOutcomes==uniqueDiscreteOutcomes(discreteOutcomesIdx);
        relevantContinuousOutcomes_curIdx = continuousOutcomes(I);
        I = discreteOutcomes==uniqueDiscreteOutcomes(discreteOutcomesIdx+1);
        relevantContinuousOutcomes_nextIdx = continuousOutcomes(I);

        % compute the number of points which are overlapping
        minCur = min(relevantContinuousOutcomes_curIdx);
        maxCur = max(relevantContinuousOutcomes_curIdx);

        numOverlapPoints = length(find(relevantContinuousOutcomes_nextIdx>=minCur & ...
                                       relevantContinuousOutcomes_nextIdx<=maxCur));

        numOverlapPtsVec(discreteOutcomesIdx) = numOverlapPoints/length(relevantContinuousOutcomes_nextIdx)*(M/length(uniqueDiscreteOutcomes));
    end
end

end
