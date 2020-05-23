% Fuction of an ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

function [Vel_hz,Vel_hz_unit,Deg_hz,Rate_vr,Rate_vr_unit,Direc_vr] = msg_vel_decode(data)
% Decode airplane ground speed info

subtype = data(6:8);

if(subtype == '001')    %subtype 1: ground speed
    Sig_ew = data(14);                  %East-West velocity sign
    Vel_ew = bin2dec(data(15:24));      %East-West velocity

    Sig_ns = data(25);                  %North-South velocity sign
    Vel_ns = bin2dec(data(26:35));      %North-South velocity 

    Src_vr = data(36);                  %Vertical rate source
    Sig_vr = data(37);                  %Vertical rate sign
    Rate_vr = bin2dec(data(38:46));     %Vertical rate

    % ---------- Horizontal Velocity calculation -----------------
    if(Sig_ew == '1')
        Vel_we = -1*(Vel_ew - 1);
    else
        Vel_we = Vel_ew - 1;
    end
    
    if(Sig_ns == '1')
        Vel_sn = -1*(Vel_ns - 1);
    else
        Vel_sn = Vel_ns - 1;
    end
    
    Vel_hz = sqrt(Vel_we^2 + Vel_sn^2);
    Deg_hz = atan2(Vel_we,Vel_sn) * 360/2/pi;
    Deg_hz = mod(Deg_hz, 360);
    
    Vel_hz = Vel_hz * 1.852; %kt to km/h
    Vel_hz_unit = 'km/h';
    
    % ------------- Vertical Velocity calculation ---------------
    if(Sig_vr == '0')
        Direc_vr = 'UP';
    else
        Direc_vr = 'DOWN';
    end
    
    Rate_vr = (Rate_vr - 1)*64*0.018288; %ft/min to km/h
    Rate_vr_unit = 'km/h';
end

end

