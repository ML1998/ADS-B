% Fuction of an ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

function [alt,Rlat,Rlong] = msg_pos_decode(msg, location)
%MSG_POS_DECODE: Decode Airbone position message CPR encoded 

% Calculate altitude
Q = msg(16);

if(Q == '1')
    alt = bin2dec(strcat(msg(9:15),msg(17:20)))*25 - 1000;
else
    alt = 0;
end

% Calculate latitude and longitude
if(msg(22) == '0')
    oeFlag = 'even';
else
    oeFlag = 'odd';
end

lat  = bin2dec(msg(23:39));
long = bin2dec(msg(40:56));

% Calculate latitude
if strcmp(oeFlag,'even')
    eff = floor(mod(location.lat, location.dlat_even)/location.dlat_even - lat/131072 + 0.5);
    Rlat = location.dlat_even*(location.a1 + eff + lat/131072);
else
    eff = floor(mod(location.lat, location.dlat_odd)/location.dlat_odd - lat/131072 + 0.5);
    Rlat = location.dlat_odd *(location.a2 + lat/131072);
end

% Calculate latitude from 17 bits
if strcmp(oeFlag,'even')
    eff = floor(mod(location.long, location.dlong_even)/location.dlong_even - long/131072 + 0.5);
    Rlong = location.dlong_even*(location.a3 + eff + long/131072);
else
    eff = floor(mod(location.long, location.dlong_odd)/location.dlong_odd - long/131072 + 0.5);
    Rlong = location.dlong_odd*(location.a4 + eff + long/131072);
end


%[ddLat,mmLat,ssLat]=ConvertFracDeg(Rlat);
%[ddLong,mmLong,ssLong]=ConvertFracDeg(Rlong);
%fprintf(sprintf('At latitude %d %d %4.1f, longitude %d %d %4.1f\n', ddLat, mmLat, ssLat, ddLong, mmLong, ssLong));

end

