% Fuction of an ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

function hex = adsb_bin2hex(bin)
% convert bin to hex
bin_arrayin4 = reshape(bin,4,length(bin)/4);
bin_arrayin4 = bin_arrayin4';
hex = dec2hex(bin2dec(bin_arrayin4));
hex = hex';
end

