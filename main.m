%% ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

%% Initialize serial port connection
clear; clc;

% check free serial ports
s_freeports = serialportlist("available");
disp("Info: Available serial ports:");
disp(s_freeports);

% select desired serial port
str = input("serial port name:", 's');
if(isempty(str)) 
    str = s_freeports; 
end

% set baud rate as 2 MHz
s = serialport(str, 2e9, "Timeout", 5);


%% Map display

% Display webmap
wm = webmap('Open Street Map');
zoomLevel = 8;

% Get center location
location.lat = input('Enter current latitude in deg (neg for southern hem) \n (eg: 39.92 for Beijing): ');
location.long = input('Enter current longitude in deg (neg for western hem) \n (eg: 116.38 for Beijing): ');

wmcenter(wm, location.lat, location.long, zoomLevel)

% Specify custom icon.
[iconFilename,iconDir] = uigetfile('*.png',...
               'Select an icon file','icon.png');
iconFilename = fullfile(iconDir, iconFilename);
h = wmmarker(location.lat, location.long, ...
                    'FeatureName', 'Beijing',... 
                    'OverlayName', 'Beijing');
                                       
%Parameter calculation for CPR encoded position
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

%% Data processing

% VAR INITIALIZATION
ICAOList = strings(0);  % List of received ICAO
MsgList = [];           % Information about the airplane
Handles = {};           % Handles to geopoint
GPList = geopoint();    % List of geopoints

adder = 0;              % Count messages with no valid information

% TEST: READ FROM A TXT FILE -----------------------
%    including of 48 messages from 3 airplanes
test = readtable('TEST_multi.txt');
test_msg = test.message;
N = size(test,1);
% --------------------------------------------------

for i = 1:1:N
    % TEST: READ LINE BY LINE ----------------------
    msg = test_msg{i};
    % ----------------------------------------------
    
    % TODO: READ FROM THE SERIAL PORT
    %   read 112 bits data from serial port
    %msg = read(s, 28, "char"); % 8*14=112bits    
   
    % Decode the message
    % Step 1: Identify S mode ADS-B message
    
    % -- First convert the message to binary form
    msg_bin = adsb_str2bin(msg);
    
    % -- Abstract DF seg to see if it is an ADS-B msg
    msg_DF = msg_bin(1:5);
    
    if (~isequal(bin2dec(msg_DF), 17))  % if not S mode ADS-B msg
        disp('Warning: illegal message'); 
        continue;                       % go to next iteration
    else
        disp('Info:  message got');
        %disp(msg);
    end
    
    % Step 2: Record 24-bit ICAO and create the struct
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

    msg_s = struct(field1,value1,field2,value2,field3,value3,...
        field4,value4,field5,value5,field6,value6,field7,value7,...
        field8,value8,field9,value9,field10,value10,field11,value11);
        
    
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
            [msg_s.Hz_Vel,msg_s.Hz_Vel_unit,msg_s.Hz_Deg,...
                    msg_s.Vr_Rate,msg_s.Vr_Rate_unit,msg_s.Vr_Dir] = msg_vel_decode(msg_data);        
        otherwise
            adder = adder+1;
            fprintf('No message got, roll %d', adder);
    end
    
    %Step 4: Add the new Aircraft info / Refresh the current info
    [lia, loc] = ismember(string(msg_ICAO), ICAOList);
    [NHrow, NHcol] = size(Handles);
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
                %fprintf('Info: ICAO: %s, ALT: %d, Lat: %s, Long: %s\n', msg_ICAO, msg_s.Alt, msg_s.Latitude, msg_s.Longitude);    
                
                %Update/Add the info in the geopoint structure
                if(~isempty(GPList))
                    [glia, gloc] = ismember(string(msg_ICAO), GPList.ICAO);
                    if(glia)    % Condition 2
                        % 2.1 update the parameter info in p
                        lat_rsv = GPList.Latitude(gloc);
                        lon_rsv = GPList.Longitude(gloc);
                        GPList.Latitude(gloc)  = msg_s.Latitude;
                        GPList.Longitude(gloc) = msg_s.Longitude;
                        GPList.Alt(gloc)       = msg_s.Alt;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember([Handles{2,:}], msg_ICAO);
                        idx = find(hloc,1);
                        wmmarker(lat_rsv, lon_rsv,  'Icon', 'trace-mark.png',...
                                                    'IconScale', 0.5); % reserve the trace
                        wmremove(Handles{1,idx});
                        
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{1,idx} = wmmarker(GPList(gloc), 'Icon',iconFilename,...
                                                           'FeatureName', msg_ICAO,... 
                                                           'OverlayName', msg_ICAO);
                        
                    else        % Condition 3.1
                        %3.1.1 add it to geopoint set p
                        p_tmp = geopoint(MsgList(loc));
                        GPList = cat(1, GPList, p_tmp);
                        %3.1.2 display it on map and store the handle
                        h = wmmarker(p_tmp, 'Icon',iconFilename,...
                                            'FeatureName', msg_ICAO,... 
                                            'OverlayName', msg_ICAO);
                        Handles{1,NHcol+1} = h;
                        Handles{2,NHcol+1} = string(msg_ICAO);   
                    end
                else %p is empty, it must not be a member of p
                     %3.1.1 add it to geopoint set p
                     GPList = geopoint(MsgList(loc));
                     %3.1.2 display it on map and store the handle
                     h = wmmarker(GPList,    'Icon',iconFilename,...
                                        'FeatureName', msg_ICAO,... 
                                        'OverlayName', msg_ICAO);
                     % store the handle
                     Handles{1,1} = h;
                     Handles{2,1} = string(msg_ICAO);
                end
                
            case 'FLAG_ID' 
                MsgList(loc).ID = msg_s.ID; 

                %Update the info in the geopoint structure
                if(~isempty(GPList))
                    [glia, gloc] = ismember(string(msg_ICAO), GPList.ICAO);
                    if(glia) % Condition 2
                        % 2.1 update the parameter info in p
                        GPList.ID(gloc)  = msg_s.ID;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember([Handles{2,:}], msg_ICAO);
                        idx = find(hloc,1);
                        wmremove(Handles{1,idx});
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{1,idx} = wmmarker(GPList(gloc), 'Icon',iconFilename,...
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
                if(~isempty(GPList))
                    [glia, gloc] = ismember(string(msg_ICAO), GPList.ICAO);
                    if(glia)  % Condition 2
                        % 2.1 update the parameter info in p
                        GPList.Hz_Vel(gloc)       = msg_s.Hz_Vel;
                        GPList.Hz_Vel_unit(gloc)  = msg_s.Hz_Vel_unit;
                        GPList.Hz_Deg(gloc)       = msg_s.Hz_Deg;
                        GPList.Vr_Rate(gloc)      = msg_s.Vr_Rate;
                        GPList.Vr_Rate_unit(gloc) = msg_s.Vr_Rate_unit;
                        GPList.Vr_Dir(gloc)       = msg_s.Vr_Dir;
                        % 2.2 delete the geopoint currently on the map
                        [hlia, hloc] = ismember([Handles{2,:}], msg_ICAO);
                        idx = find(hloc,1);
                        wmremove(Handles{1,idx});
                        % 2.3 insert a new point on map, update the handler in Handles
                        Handles{1,idx} = wmmarker(GPList(gloc), 'Icon',iconFilename,...
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
            if(isempty(GPList))
                GPList = geopoint(msg_s);
                h = wmmarker(GPList, 'FeatureName', msg_ICAO,...
                                'Icon',iconFilename,...
                                'OverlayName', msg_ICAO);
                % store the handle
                Handles{1,1} = h;
                Handles{2,1} = string(msg_ICAO);
            else
                p_tmp = geopoint(msg_s);
                GPList = cat(1, GPList, p_tmp);
                h = wmmarker(p_tmp, 'Icon',iconFilename,...
                                    'FeatureName', msg_ICAO,... 
                                    'OverlayName', msg_ICAO);
                % store the handle
                Handles{1,NHcol+1} = h;
                Handles{2,NHcol+1} = string(msg_ICAO);     
            end
        end
    end
    
    %Step 5: Update all received info
    T = struct2table(MsgList);
    %disp(T);
    %disp(Handles);
    writetable(T,'AdsBData.txt','Delimiter',' ')  
    
    %Step 6: Display all geopoints on webmap


end

%% End the program

wmclose;
flush(s);
clear s;

