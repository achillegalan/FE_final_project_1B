function [Agrid, Bgrid, SSEgrid, minPoint] = plotMHWabObjectiveLandscape( ...
    OIS_curve, EUR3M_curve, diagData, gamma, isPayer, aVec, bVec, isCS)
%PLOTMHWABOBJECTIVELANDSCAPE Plots Err2(a,b) for diagonal-swaption calibration.
%
%   [Agrid,Bgrid,SSEgrid,minPoint] = plotMHWabObjectiveLandscape( ...
%       OIS_curve, EUR3M_curve, diagData, gamma, isPayer, aVec, bVec)
%
% Computes:
%   Err2(a,b) = sum_i (PriceModel_i(a,b,gamma) - PriceMkt_i)^2
% on a (a,b) grid and shows:
%   1) filled contour of log10(Err2)
%   2) surface of log10(Err2)
%
% INPUT
%   OIS_curve, EUR3M_curve  Curve structs.
%   diagData                Struct with field .summary and columns:
%                           ExpiryYears, TenorYears, StrikeATM, MarketPrice.
%   gamma                   Fixed gamma in [0,1].
%   isPayer                 true/false (default true).
%   aVec                    Grid values for a (default linspace(0,0.40,31)).
%                           Non-negative values are allowed (including 0).
%   bVec                    Grid values for b (default linspace(0,0.40,31)).
%                           Non-negative values are allowed (including 0).
%   isCS                    true for CS pricing (default true), false for PD.
%
% OUTPUT
%   Agrid, Bgrid            Meshgrid matrices for plotting.
%   SSEgrid                 Objective value on the grid (NaN if pricing fails).
%   minPoint                Struct with best grid point (a,b,sse,validMask).

    % Always include the boundary points a=0 and b=0 in the plotted grid.
    aVec = unique([aVec(:).', 0], 'sorted');
    bVec = unique([bVec(:).', 0], 'sorted');

    mkt = diagData.summary;
    expiryYears = mkt.ExpiryYears(:);
    tenorYears = mkt.TenorYears(:);
    strikeATM = mkt.StrikeATM(:);
    marketPrices = mkt.MarketPrice(:);

    n = numel(expiryYears);
    settleDate = OIS_curve.settlementDate;

    % Precompute schedules once (large speedup vs rebuilding at each grid point).
    floatPayDatesCell = cell(n, 1);
    fixedPayDatesCell = cell(n, 1);
    for i = 1:n
        exDate = add_target_months(settleDate, round(12 * expiryYears(i)), 'modifiedfollow');
        matDate = add_target_months(exDate, round(12 * tenorYears(i)), 'modifiedfollow');
        floatSched = makeSchedule(exDate, matDate, 3, 'modifiedfollow');
        fixedSched = makeSchedule(exDate, matDate, 12, 'modifiedfollow');
        floatPayDatesCell{i} = floatSched(2:end);
        fixedPayDatesCell{i} = fixedSched(2:end);
    end

    [Agrid, Bgrid] = meshgrid(aVec, bVec);
    SSEgrid = nan(size(Agrid));

    for ib = 1:numel(bVec)
        bTry = bVec(ib);
        for ia = 1:numel(aVec)
            aTry = aVec(ia);
            SSEgrid(ib, ia) = objectiveSSE(aTry, bTry);
        end
    end

    validMask = isfinite(SSEgrid);
    if ~any(validMask(:))
        error('plotMHWabObjectiveLandscape:NoValidGridPoint', ...
            'All grid evaluations failed. Try a different (a,b) range.');
    end

    sseForMin = SSEgrid;
    sseForMin(~validMask) = inf;
    [sseMin, linIdx] = min(sseForMin(:));
    aMin = Agrid(linIdx);
    bMin = Bgrid(linIdx);

    plotSSE = SSEgrid;
    zMin = sseMin;

    figure('Name', 'Err2(a,b) objective landscape');
    tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    contourf(Agrid, Bgrid, plotSSE, 24, 'LineStyle', 'none');
    hold on;
    plot(aMin, bMin, 'kp', 'MarkerFaceColor', 'y', 'MarkerSize', 11);
    hold off;
    xlabel('a');
    ylabel('b');
    title('Err2(a,b) contour');
    cb1 = colorbar;
    cb1.Label.String = 'Err2 (SSE)';
    xlim([min(aVec), max(aVec)]);
    ylim([min(bVec), max(bVec)]);
    grid on;

    nexttile;
    surf(Agrid, Bgrid, plotSSE, 'EdgeColor', 'none');
    hold on;
    plot3(aMin, bMin, zMin, 'kp', 'MarkerFaceColor', 'y', 'MarkerSize', 11);
    hold off;
    xlabel('a');
    ylabel('b');
    zlabel('Err2 (SSE)');
    title('Err2(a,b) surface');
    cb2 = colorbar;
    cb2.Label.String = 'Err2 (SSE)';
    xlim([min(aVec), max(aVec)]);
    ylim([min(bVec), max(bVec)]);
    view(45, 30);
    grid on;

    minPoint = struct();
    minPoint.a = aMin;
    minPoint.b = bMin;
    minPoint.sse = sseMin;
    minPoint.validMask = validMask;

    function sse = objectiveSSE(aTry, bTry)
        modelTry = modelPricesFromParams(aTry, bTry);
        if any(~isfinite(modelTry))
            sse = nan;
            return;
        end

        r = modelTry - marketPrices;
        sse = sum(r.^2);
        if ~isfinite(sse)
            sse = nan;
        end
    end

    function modelVec = modelPricesFromParams(aTry, bTry)
        modelVec = nan(n, 1);
        for i = 1:n
            try
                modelVec(i) = model_multiHJM_Price( ...
                    OIS_curve, EUR3M_curve, floatPayDatesCell{i}, fixedPayDatesCell{i}, ...
                    strikeATM(i), expiryYears(i), aTry, bTry, gamma, isPayer, isCS);
            catch
                return;
            end
        end
    end
end
