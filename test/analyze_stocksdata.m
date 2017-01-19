%**************************************************************************
%*                                                                        *
%* Copyright (C) 2016  Kiran Karra <kiran.karra@gmail.com>                *
%*                                                                        *
%* This program is free software: you can redistribute it and/or modify   *
%* it under the terms of the GNU General Public License as published by   *
%* the Free Software Foundation, either version 3 of the License, or      *
%* (at your option) any later version.                                    *
%*                                                                        *
%* This program is distributed in the hope that it will be useful,        *
%* but WITHOUT ANY WARRANTY; without even the implied warranty of         *
%* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          *
%* GNU General Public License for more details.                           *
%*                                                                        *
%* You should have received a copy of the GNU General Public License      *
%* along with this program.  If not, see <http://www.gnu.org/licenses/>.  *
%*                                                                        *
%**************************************************************************

%% Analyze the pair-wise RSDM metrics for as much alingned data as possible
% for all the available stock prices & save results

clear;
clc;
dbstop if error;

if(ispc)
    rootDir = 'C:\\Users\\Kiran\\ownCloud\\PhD\\sim_results\\stocks';
elseif(ismac)
    rootDir = '/Users/Kiran/ownCloud/PhD/sim_results/stocks';
else
    rootDir = '/home/kiran/ownCloud/PhD/sim_results/stocks';
end

% list all available data
files = dir(fullfile(rootDir,'normalized_files'));
numStocksToProcess = length(files)-2;   % the -2 is to exclude '.' and '..'
stocksData = cell(numStocksToProcess,4);   
                                        % {1} = stock name
                                        % {2} = raw data
                                        % {3} = first difference of closing
                                        %       price
                                        % {4} = results of augmented
                                        %       dickey-fuller test of
                                        %       stationarity

% https://www.kevinsheppard.com/images/9/95/MFE_Toolbox_Documentation.pdf
% See Page 57 for why the two options below make sense
adfTestType = 0;    % 0 : No deterministic terms
                    % 1 : Constant
                    % 2 : Time Trend
                    % 3 : Constant, DGP assumed to have a time trend
lags = 0;           % the # of lags to test for
                                        
% read it all in
jj = 1;
for ii=1:length(files)
    fname = files(ii).name;
    [~,name,ext] = fileparts(fname);
    if(strcmpi(ext,'.csv'))
        fnameWithPath = fullfile(rootDir, 'normalized_files', fname);
        fprintf('Processing file=%s\n', fnameWithPath);
        % process this file
        fid = fopen(fnameWithPath);
        header = fgetl(fid);
        data = textscan(fid, '%*s %f %f %f %f %*[^\n]', 'delimiter', ',');
        fclose(fid);
        
        stocksData{jj,1} = name;
        stocksData{jj,2} = data;
        closePrice = data{4};
        % compute returns data
        returnsData = closePrice(1:end-1)-closePrice(2:end);
        stocksData{jj,3} = returnsData;
        % compute augmented dickey-fuller test of stationarity on the
        % returns
        [adftest.stat,adftest.pval,adftest.critval,adftest.resid] = ...
            augdf(returnsData,adfTestType,lags);
        stocksData{jj,4} = adftest;
        
        jj = jj + 1;
    end
end

% start the parallel pool if none exist
p = gcp();

% suppress rank-deficient warnings for regression fitting (we aren't
% concerned with that for our current analysis)
pctRunOnAll warning('off','MATLAB:rankDeficientMatrix');

% now perform monotonicity analysis
R = zeros(numStocksToProcess,numStocksToProcess);
RectanglesCell = cell(numStocksToProcess,numStocksToProcess);
for ii=1:numStocksToProcess
    fprintf('Processing Data # %d\n', ii);
    parfor jj=ii+1:numStocksToProcess
        returns_i = stocksData{ii,3};
        returns_j = stocksData{jj,3};
        numSampsToProcess = min(length(returns_i),length(returns_j));
        returns_i = returns_i(1:numSampsToProcess);
        returns_j = returns_j(1:numSampsToProcess);
        [metric, rectangleCellOut] = rsdm(returns_i,returns_j);
        
        R(ii,jj) = metric; 
        RectanglesCell{ii,jj} = rectangleCellOut;
    end
end

for ii=1:numStocksToProcess
    for jj=ii+1:numStocksToProcess
        R(jj,ii) = R(ii,jj); 
        R(ii,ii) = 1;
        RectanglesCell{jj,ii} = RectanglesCell{ii,jj};
    end
end

sz = size(RectanglesCell);
monotonicityMat = zeros(sz);
for jj=1:sz(1)
    for kk=jj+1:sz(2)
        rco = RectanglesCell{jj,kk};
        monotonicityMat(jj,kk) = size(rco,2);
        monotonicityMat(kk,jj) = size(rco,2);
    end
end
% count the proportion of pairwise dependencies that are monotonic,
% and the # of times the nonmonotonicity occurs.  only count the
% upper-triangle
I = triu(monotonicityMat,1)~=0;
monotonicityVec = monotonicityMat(I);
[uniques, numUniques] = count_unique(monotonicityVec);

% restore normal Matlab warning settings
pctRunOnAll warning('on','MATLAB:rankDeficientMatrix');

p = gcp('nocreate');
delete(p)

outFile = fullfile(rootDir,'stocks_results.mat');
save(outFile);

%% Plot the Monotonicity results of the above
clear;
clc;
dbstop if error;

if(ispc)
    rootDir = 'C:\\Users\\Kiran\\ownCloud\\PhD\\sim_results\\stocks';
elseif(ismac)
    rootDir = '/Users/Kiran/ownCloud/PhD/sim_results/stocks';
else
    rootDir = '/home/kiran/ownCloud/PhD/sim_results/stocks';
end
load(fullfile(rootDir,'stocks_results.mat'));

numStocksProcessed = size(monotonicityMat,1);
alpha = 0.05;       % significance level for Dickey-Fuller tests
% we only aggregate results for where the Dickey-Fuller confirms that the
% data is indeed stationary
validIdxs = zeros(1,numStocksProcessed);
for ii=1:numStocksProcessed
    adfTestResults = stocksData{ii,4};
    if(adfTestResults.pval < alpha)
        validIdxs(ii) = 1;
    end
end

depThreshVec = [0.01 0.05 0.1 0.15 0.2 0.25];
finalMonotonicityResults = cell(1,length(depThreshVec));

for zz=1:length(depThreshVec)
    depThresh = depThreshVec(zz);
    fprintf('Processing depThresh=%0.02f\n', depThresh);
    monotonicityResults = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
    for ii=1:numStocksProcessed
        for jj=ii+1:numStocksProcessed
            if(validIdxs(ii) && validIdxs(jj))
                % means both stocks returns data are stationary

                % make sure that this pairwise computation is not independent
                rsdmVal = R(ii,jj);
                returns_i = stocksData{ii,3};
                returns_j = stocksData{jj,3};
                numSampsToProc = min(length(returns_i),length(returns_j));
                tauklVal = abs(taukl(returns_i(1:numSampsToProc),returns_j(1:numSampsToProc)));
                percentageDiff = abs(rsdmVal-tauklVal)/tauklVal;
                if(percentageDiff<=depThresh)
                    monotonicityMat(ii,jj) = 1;
                    monotonicityMat(jj,ii) = 1;
                end
                numMonotonicRegions = monotonicityMat(ii,jj);

                numSampsProcessed = min(length(returns_i),length(returns_j));
                pval = rsdmpval(rsdmVal, numSampsProcessed);
                if(pval<alpha)

                    if(isKey(monotonicityResults,numMonotonicRegions))
                        monotonicityResults(numMonotonicRegions) = monotonicityResults(numMonotonicRegions) + 1;
                    else
                        monotonicityResults(numMonotonicRegions) = 1;
                    end
                end
            end
        end
    end
    keys(monotonicityResults)
    values(monotonicityResults)
    finalMonotonicityResults{zz} = monotonicityResults;
end

% save off the results
save(fullfile(rootDir, 'finalMonotonicityResults.mat'), 'finalMonotonicityResults', 'depThreshVec');

%% plot the final monotonicityResults

clear;
clc;

if(ispc)
    rootDir = 'C:\\Users\\Kiran\\ownCloud\\PhD\\sim_results\\stocks';
elseif(ismac)
    rootDir = '/Users/Kiran/ownCloud/PhD/sim_results/stocks';
else
    rootDir = '/home/kiran/ownCloud/PhD/sim_results/stocks';
end
load(fullfile(rootDir,'finalMonotonicityResults.mat'));


maxCount = 0;
for ii=1:length(depThreshVec)
    if(finalMonotonicityResults{ii}.Count>maxCount)
        maxCount = finalMonotonicityResults{ii}.Count;
    end
end

barPlotVec = zeros(maxCount, length(depThreshVec));
for ii=1:length(depThreshVec)
    c = finalMonotonicityResults{ii};
    for jj=1:maxCount
        if(isKey(c,jj))
            val = double(c(jj));    % potentially experiment w/ transforms, 
                                    % log is one
                                    % x/(a+x) is another one
                                    % both diminish the effect of how prevalent
                                    % monotonic dependencies are in the data,
                                    % so for now we leave it as is.
        else
            val = 0;
        end
        valToPlot = val;
        barPlotVec(ii,jj) = valToPlot;
    end
    numTotalPairwiseDepsAnalyzed = sum(barPlotVec(ii,:));
    barPlotVec(ii,:) = barPlotVec(ii,:)/sum(barPlotVec(ii,:)) * 100;
end

barX = depThreshVec*100;
h = bar(barX, barPlotVec,'stacked');
hold on
plot(xlim,[95 95], 'r--', 'LineWidth', 4)
grid on;
fontSize = 20;
xlabel('Tolerance %', 'FontSize', fontSize, 'FontWeight', 'bold')
ylabel('% of total dependencies', 'FontSize', fontSize, 'FontWeight', 'bold');
a = 1:maxCount;
legendCell = cellstr(num2str(a(:)));
legendCell = legendCell.';
lh = legend(legendCell, 'location', 'southeast');
v = get(lh,'title');
set(v,'string',{'# Monotonic', 'Regions'});
title({sprintf('Monotonicity of %d pairwise dependencies analyzed', ...
    numTotalPairwiseDepsAnalyzed), 'for returns of Major Stock indices'}, ...
    'FontSize', fontSize, 'FontWeight', 'bold');

xt = get(gca, 'XTick');
set(gca, 'XTick', barX);
set(gca, 'YTick', [20 40 60 80 95]);
ylim([0 100])
set(gca, 'FontSize', 28)