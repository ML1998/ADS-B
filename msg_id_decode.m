% Fuction of an ADS-B message processor 
%       by Mingyu Lei <mingyulei98@gmail.com> at UCAS
%       Electronic System Design
%       Spring 2020

function out_id = msg_id_decode(msg_data)
% Decode the aircraft ID based on the 56-bit code

% Look up table: 
%   A - Z :   1 - 26
%   0 - 9 :  48 - 57
%       _ :  32

data = msg_data(9:56);
data = reshape(data,6,8);
data = data';
data = bin2dec(data);
result = zeros(1,8);

for j = 1:8
    if (data(j) < 27)
        result(j) = data(j)-1+65; %A -- 65
    else if(data(j) == 32)
            result(j) = '_';
        else if(data(j) > 47 && data(j) < 58)
                result(j) = data(j); %0 -- 48
            else
                disp('illegal aircraft ID');
            end
        end
    end
end
out_id = char(result);
end

