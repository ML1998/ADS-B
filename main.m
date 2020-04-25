%% ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

%% Initialize serial port (virtual)
clear; clc;

s_freeports = serialportlist("available");
disp("Info: Available serial ports:");
disp(s_freeports);

str = input("serial port name:", 's');
if(isempty(str)) 
    str = s_freeports; 
end
s = serialport(str, 9600, "Timeout", 5);

%% Input current location info and map init

%Get center location
location.lat = input('Enter current latitude in degrees (neg for southern hemisphere) \n (example: 39.92 for Beijing): ');
location.long = input('Enter current longitude in degrees (neg for western hemisphere) \n (example: 116.38 for Beijing): ');

%Parameter calculation
location.dlat_even = 360/60;
location.a1 = floor(location.lat/location.dlat_even);
    
location.dlat_odd = 360/59;
location.a2 = floor(location.lat/location.dlat_odd);
    
NL=2:59;
latzones = [(180/pi)*acos(sqrt((1-cos(pi/2/15))./(1-cos(2*pi./NL)))) 0];
    
NL0 = find(latzones<location.lat,1,'first');
  
location.dlong_even = 360/NL0;
location.a3 = floor(location.long/location.dlong_even);
    
location.dlong_odd = 360/(NL0-1);
location.a4 = floor(location.long/location.dlong_odd);

%Map display
wm = webmap('Open Street Map');
zoomLevel = 8;
wmcenter(wm, location.lat, location.long, zoomLevel)
[latlim,lonlim] = wmlimits(wm);
% Specify custom icon.
[iconFilename,iconDir] = uigetfile('*.png',...
               'Select an icon file','icon.png');
iconFilename = fullfile(iconDir, iconFilename);
h = wmmarker(location.lat, location.long, ...
                    'FeatureName', 'Beijing',... 
                    'OverlayName', 'Beijing');
                    %'IconScale',0.1);
                
%% Get data from serial port
clc;
%flush after N cycles
N = 4;
adder = 0;
ICAOList = strings(0);
MsgList = [];
handles = {};
p = geopoint();

for i = 1:1:N
    %read 112 bits data from serial port
    % msg = read(s, 28, "char"); % 8bits * 14 = 112 bits
    
    %Todo: 
    %  1. For simulation purposes: change to read from a txt file 
    %  2. Methods of Dealing with serial port 
        
    if(i==1)
        msg = '8D4840D6202CC371C32CE0576098'; %ID
    elseif(i==2)
        msg = '8D40621D58C382D690C8AC2863A7'; %pos
    elseif(i==3)
        msg = '8D40621D994409940838175B284F'; %ground speed
    elseif(i==4)
        msg = '8D40621D202CC371C32CE0576098'; %ID
    end
    
    msg_bin = adsb_str2bin(msg);% convert to binary
    
    % Decode the message
    % Step 1: Identify S mode ADS-B message
    msg_DF = msg_bin(1:5);
    if (~isequal(bin2dec(msg_DF), 17)) % if not S mode ADS-B msg
        disp('Warning: illegal message'); 
        continue; % go to next iteration
    else
        disp('Info:  message got');
    end
    
    % Step 2: Record 24-bit ICAO and create struct
    msg_ICAO = adsb_bin2hex(msg_bin(9:32));
        
    field1 = 'ICAO';            value1 = msg_ICAO;
    field2 = 'ID';              value2 = missing;
    field3 = 'Alt';             value3 = missing;
    field4 = 'Latitude';        value4 = missing;
    field5 = 'Longitude';       value5 = missing;
    field6 = 'Hz_Vel';          value6 = missing;
    field7 = 'Hz_Vel_unit';     value7 = "";
    field8 = 'Hz_Deg';          value8 = missing;
    field9 = 'Vr_Rate';         value9 = missing;
    field10 = 'Vr_Rate_unit';   value10 = "";
    field11 = 'Vr_Dir';         value11 = missing;

    msg_s = struct(field1,value1,field2,value2,field3,value3,field4,value4,...
        field5,value5,field6,value6,field7,value7,field8,value8,field9,value9,field10,value10);
        
    
    % Step 3: Identify message type
    msg_data = msg_bin(33:88);
    msg_data_type = bin2dec(msg_data(1:5));
    
    msg_data_flag = 'FLAG_INI';
    if (msg_data_type > 0 && msg_data_type < 5)
        msg_data_flag = 'FLAG_ID';
    elseif (msg_data_type < 9)
        msg_data_flag = 'FLAG_POS';
    elseif (msg_data_type < 19)
        msg_data_flag = 'FLAG_POS';
    elseif (msg_data_type == 19)
        msg_data_flag = 'FLAG_VELOCITY'; 
    elseif (msg_data_type < 23)
        msg_data_flag = 'FLAG_POS';
    end
    
    fprintf('Info:  message type -- %s\n', msg_data_flag);
    
    switch (msg_data_flag)
        case 'FLAG_POS'
            [msg_s.Alt, msg_s.Latitude, msg_s.Longitude] = msg_pos_decode(msg_data, location);
        case 'FLAG_ID' 
            msg_s.ID = msg_id_decode(msg_data);
        case 'FLAG_VELOCITY'
            [msg_s.Hz_Vel,msg_s.Hz_Vel_unit,msg_s.Hz_Deg,msg_s.Vr_Rate,msg_s.Vr_Rate_unit,msg_s.Vr_Dir] = msg_vel_decode(msg_data);        
        otherwise
            adder = adder+1;
            fprintf('No message got, roll %d', adder);
    end
    
    %Step 4: Add the new Aircraft info / Refresh the current info
    [lia, loc] = ismember(string(msg_ICAO), ICAOList);
    
    if(lia) 
        %Refresh the current info if it is a member
        % This is not the first time we receive messages from this aircraft
        % 
        % 1. First update the existing MsgList element, regardless of the
        % type of message.
        %
        % 2. If it is a member of geopoint set p, we should 
        %       2.1 update the parameter info in p
        %       2.2 delete the geopoint currently on the map
        %       2.3 insert a new point on map, update the handler in Handles
        % 
        % 3. If it is NOT a member of geopoint set p, we should judge
        % whether it is a 'FLAG_POS' type. 
        %       3.1 If YES:
        %           3.1.1 add it to geopoint set p
        %           3.1.2 display it on map and store the handle
        %       3.2 If NO:
        %           do nothing
        
        switch (msg_data_flag)
            case 'FLAG_POS'
                MsgList(loc).Alt = msg_s.Alt;
                MsgList(loc).Latitude  = msg_s.Latitude;
                MsgList(loc).Longitude = msg_s.Longitude;    
                
                %Update/Add the info in the geopoint structure
                if(~isempty(p))
                    [glia, gloc] = ismember(string(msg_ICAO), p.ICAO);
                    if(glia)    % Condition 2
                        % 2.1 update the parameter info in p
                        p.Latitude(gloc)  = msg_s.Latitude;
                        p.Longitude(gloc) = msg_s.Longitude;
                        p.Alt(gloc)       = msg_s.Alt;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember(string(Handles(2,:)), msg_ICAO);
                        idx = find(hloc,1);
                        wmremove(Handles{idx,1});
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{idx,1} = wmmarker(p(gloc), 'Icon',iconFilename,...
                                                           'FeatureName', msg_ICAO,... 
                                                           'OverlayName', msg_ICAO);
                        
                    else        % Condition 3.1
                        %3.1.1 add it to geopoint set p
                        p_tmp = geopoint(MsgList(loc));
                        p(length(p)+1) = p_tmp;
                        %3.1.2 display it on map and store the handle
                        h = wmmarker(p_tmp, 'Icon',iconFilename,...
                                            'FeatureName', msg_ICAO,... 
                                            'OverlayName', msg_ICAO);
                        Handles{1,length(Handles)+1} = h;
                        Handles{2,length(Handles)+1} = string(msg_ICAO);   
                    end
                end
                
            case 'FLAG_ID' 
                MsgList(loc).ID = msg_s.ID; 

                %Update the info in the geopoint structure
                if(~isempty(p))
                    [glia, gloc] = ismember(string(msg_ICAO), p.ICAO);
                    if(glia) % Condition 2
                        % 2.1 update the parameter info in p
                        p.ID(gloc)  = msg_s.ID;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember(string(Handles(2,:)), msg_ICAO);
                        idx = find(hloc,1);
                        wmremove(Handles{idx,1});
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{idx,1} = wmmarker(p(gloc), 'Icon',iconFilename,...
                                                           'FeatureName', msg_ICAO,... 
                                                           'OverlayName', msg_ICAO);
                    end
                end
                
            case 'FLAG_VELOCITY'
                MsgList(loc).Hz_Vel         = msg_s.Hz_Vel;     
                MsgList(loc).Hz_Vel_unit    = msg_s.Hz_Vel_unit;
                MsgList(loc).Hz_Deg         = msg_s.Hz_Deg;
                MsgList(loc).Vr_Rate        = msg_s.Vr_Rate;
                MsgList(loc).Vr_Rate_unit   = msg_s.Vr_Rate_unit;
                MsgList(loc).Vr_Dir         = msg_s.Vr_Dir;
                
                %Update the info in the geopoint structure
                if(~isempty(p))
                    [glia, gloc] = ismember(string(msg_ICAO), p.ICAO);
                    if(glia)  % Condition 2
                        % 2.1 update the parameter info in p
                        p.Hz_Vel(gloc)       = msg_s.Hz_Vel;
                        p.Hz_Vel_unit(gloc)  = msg_s.Hz_Vel_unit;
                        p.Hz_Deg(gloc)       = msg_s.Hz_Deg;
                        p.Vr_Rate(gloc)      = msg_s.Vr_Rate;
                        p.Vr_Rate_unit(gloc) = msg_s.Vr_Rate_unit;
                        p.Vr_Dir(gloc)       = msg_s.Vr_Dir;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember(string(Handles(2,:)), msg_ICAO);
                        idx = find(hloc,1);
                        wmremove(Handles{idx,1});
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{idx,1} = wmmarker(p(gloc), 'Icon',iconFilename,...
                                                           'FeatureName', msg_ICAO,... 
                                                           'OverlayName', msg_ICAO);
                    end
                end
        end
    else
        %Add the new Aircraft info if it is not a member
        % *We get the first message from this Aircraft
        % *Display it on map if regarding position 
        % *Otherwise, just store the message
        
        MsgList = [MsgList, msg_s];
        ICAOList = [ICAOList, string(msg_ICAO)];
        
        if(strcmp(msg_data_flag,'FLAG_POS')) 
            if(isempty(p))
                p = geopoint(msg_s);
                h = wmmarker(p, 'FeatureName', msg_ICAO,...
                                'Icon',iconFilename,...
                                'OverlayName', msg_ICAO);
                % store the handle
                Handles{1,1} = h;
                Handles{2,1} = string(msg_ICAO);
            else
                p_tmp = geopoint(msg_s);
                p(length(p)+1) = p_tmp;
                h = wmmarker(p_tmp, 'Icon',iconFilename,...
                                    'FeatureName', msg_ICAO,... 
                                    'OverlayName', msg_ICAO);
                % store the handle
                Handles{1,length(Handles)+1} = h;
                Handles{2,length(Handles)+1} = string(msg_ICAO);     
            end
        end
    end
    
    %Step 5: Update all received info
    T = struct2table(MsgList);
    disp(T);
    writetable(T,'AdsBData.txt','Delimiter',' ')  
    
    %Step 6: Display all geopoints on webmap


end

%% Free the serial port
wmclose;
flush(s);
clear s;