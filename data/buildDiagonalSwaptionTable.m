function diagTable = buildDiagonalSwaptionTable(expiryVec, tenorVec, source)
%BUILDDIAGONALSWAPTIONTABLE Build diagonal swaption table from market cubes.
%
% INPUT
%   expiryVec  numeric vector of expiries in years 
%   tenorVec   numeric vector of tenors in years   
%   source     '2022' or '2023'
%
% OUTPUT
%   diagTable  table with columns: Expiry, Tenor, NormalVol_bps

    expiryVec = expiryVec(:);
    tenorVec = tenorVec(:);

    switch lower(string(source))
        case "2022"
            volsData = loadSwaptionVols();
        case "2023"
            volsData = loadSwaptionVolsUnwinding();
    end

    cubeExpiryYears = [1 3 6 9 12 24 36 48 60 72 84 96 108 120 144 180 240 300 360]'/12;
    cubeTenorYears = [1 2 3 4 5 7 10 12 15 20 25 30]';

    [~, idxExpiry] = ismember(expiryVec, cubeExpiryYears);
    [~, idxTenor] = ismember(tenorVec, cubeTenorYears);

    linearIdx = sub2ind(size(volsData.matrix), idxExpiry, idxTenor);
    normalVolBps = volsData.matrix(linearIdx);

    expiryLabels = string(compose('%gy', expiryVec));
    tenorLabels = string(compose('%gy', tenorVec));

    diagTable = table(expiryLabels, tenorLabels, normalVolBps, ...
        'VariableNames', {'Expiry', 'Tenor', 'NormalVol_bps'});
end
