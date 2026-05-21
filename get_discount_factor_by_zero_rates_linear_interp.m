function discount = get_discount_factor_by_zero_rates_linear_interp(reference_date, interp_date, dates, discount_factors)
% The function, given a list of discount factors, returns the discount factor at a given date by linear
% interpolation.
% REMARK:In our function, the discount factors are firstly transformed in zero rates, we interpolate the zero rates
%        and in order to give back the requested discount factor we trasform the interpolated zero rate in discount factor.
%        This is done because interpolating directly the discount factors may return "bad" interpolated discount factors.

%% INPUTS:
% reference_date:   reference date
% interp_date:      date in which we want to get the df by interpolation of
%                   the zero rates
% dates:            vector ofdates in which we have already available the dfs
% discount_factors: vector of the available dfs

%% OUTPUTS:
% discount: discount factor at the interpolation date


% Calculate the year frac of the interpolation date using Act/360 convention
t_star = yearfrac(reference_date, interp_date, 2);
    
% Calculate the vector of year fracs of the given dates
taus = yearfrac(reference_date, dates, 2);
    
% Initialize zero rates vector
z = zeros(length(discount_factors), 1);
    
% Convert discounts in zero rates
% In order to obtain an acceptable result, if the year frac is really
% small, we use 10^-12 as year frac. This hopefully will be an helpful
% thing in order to not divide the log(DF) by something that is really
% close to zero
for i = 2:length(discount_factors)
    z(i) = -log(discount_factors(i)) / max(taus(i), 1e-12);
end
    
% Linear interpolation on the interpolation date
z_star = interp1(taus, z, t_star, 'linear','extrap');
    
% Convert the just found zero rate z_star in DF
discount = exp(-z_star .* t_star);
end