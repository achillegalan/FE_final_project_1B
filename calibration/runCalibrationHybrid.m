function [hybridTable, out] = runCalibrationHybrid( ...
    years, gammas, OISBoots, EURBoots, diagMkt, isPayer, isCS)
%RUNCALIBRATIONHYBRID Run hybrid MHW calibration on multiple years/gammas.
%
% INPUT
%   years                 Numeric vector (e.g. [2022, 2023]).
%   gammas                Gamma vector (e.g. [0, 0.5, 1]).
%   OISBoots, EURBoots    Cell arrays of bootstrapped curves (one per year).
%   diagMkt               Cell array of diagonal market data (one per year).
%   isPayer               true/false (default true).
%   isCS                  true/false for CS convention (default true).
%
% OUTPUT
%   hybridTable           Long-format table with Year/Gamma/a/b/SSE/RMSE.
%   out                   Struct with matrices and full calibration diagnostics.

    if nargin < 6 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 7 || isempty(isCS)
        isCS = true;
    end

    nYears = numel(years);
    nGammas = numel(gammas);

    if nYears ~= numel(OISBoots) || nYears ~= numel(EURBoots) || nYears ~= numel(diagMkt)
        error('runCalibrationHybrid:InputSizeMismatch', ...
            'years, OISBoots, EURBoots and diagMkt must have the same length.');
    end

    aHybrid = zeros(nYears, nGammas);
    bHybrid = zeros(nYears, nGammas);
    sseHybrid = zeros(nYears, nGammas);
    rmseHybrid = zeros(nYears, nGammas);
    calHybrid = cell(nYears, nGammas);

    for iy = 1:nYears
        for ig = 1:nGammas
            g = gammas(ig);

            [aHybrid(iy, ig), bHybrid(iy, ig), calHybrid{iy, ig}] = ...
                calibrateMHWabDiagonalHybrid( ...
                    OISBoots{iy}, EURBoots{iy}, diagMkt{iy}, g, isPayer, isCS);

            sseHybrid(iy, ig) = calHybrid{iy, ig}.sse;
            rmseHybrid(iy, ig) = calHybrid{iy, ig}.rmse;

            fprintf('[Hybrid - %d, gamma=%.1f, CS] a=%.8f, b=%.8f, SSE=%.6e, RMSE=%.6e\n', ...
                years(iy), g, aHybrid(iy, ig), bHybrid(iy, ig), ...
                sseHybrid(iy, ig), rmseHybrid(iy, ig));
        end
    end

    hybridTable = table( ...
        repelem(years(:), nGammas), ...
        repmat(gammas(:), nYears, 1), ...
        reshape(aHybrid.', [], 1), ...
        reshape(bHybrid.', [], 1), ...
        reshape(sseHybrid.', [], 1), ...
        reshape(rmseHybrid.', [], 1), ...
        'VariableNames', {'Year', 'Gamma', 'a', 'b', 'SSE', 'RMSE'});

    out = struct();
    out.years = years;
    out.gammas = gammas;
    out.a = aHybrid;
    out.b = bHybrid;
    out.sse = sseHybrid;
    out.rmse = rmseHybrid;
    out.calib = calHybrid;

   
end