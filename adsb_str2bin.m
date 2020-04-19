% Fuction of an ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

function bin = adsb_str2bin(msg)
% convert hex string to 112-bit bin message

res = reshape(msg,4,length(msg)/4);
bin_array = dec2bin(hex2dec(res'));
bin = reshape(bin_array',1,length(msg)*4);
end

