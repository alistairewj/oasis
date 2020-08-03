function [ oasis, oasis_comp, comp_header ] = oasis_matlab(data,header)
%GETOASIS	Calculate OASIS from hard-coded score
%	[ OASIS ] = oasis_matlab(DATA, HEADER) outputs OASIS - a severity score
%	for intensive care unit patients. The score is calculated by binning
%	patient data and assigning each bin a pre-determined score. These
%	scores are summed across variables to provide the final score.
%
%	Inputs:
%		DATA	- NxD numeric matrix containing observations (rows) and
%			variables (columns). Certain variables are required.
%		HEADER	- 1xD cell array of strings providing the label for each
%			column of data. The following strings are required by OASIS:
%		
%   {'elect','PRELOS','age','gcs','hr','map','rr','temp','urine','vent'};
%
% The following describes the input format for each variable.
% Values which can be measured repeatedly (e.g. heart rate) should be extracted as the 
% *worst* value over the first 24 hours, i.e. the value that results in the highest score.
%
%	'elect' - Binary (0 or 1) - yes/no was the patient admitted for elective surgery
%	'PRELOS' - Numeric, >0 - Hours between patient's hospital admission and ICU admission
%	'age' - Numeric, >0 - Age measured in years
%	'gcs' - Numeric, >=3, <=15 - Glasgow Coma Scale, a measure of neurological function
%	'hr' - Numeric, >0 - Heart rate, beats per minute
%	'map' - Numeric, >0 - Mean arterial pressure, mmHg
%	'rr' - Numeric, >0 - Respiratory rate, breaths per minute
%	'temp' - Numeric, >0 - Temperature, in Celsius
%	'urine' - Numeric, >=0 - Urine output, sum over the first 24 hours, in millilitres
%	'vent' - Binary (0 or 1) - yes/no was the patient mechanically ventilated in the first 24 hours
%
%	Outputs:
%		OASIS	- Nx3 numeric matrix of scores for each observation. The three columns are:
%			column 1: the original OASIS score
%			column 2: the score calibrated to predict hospital mortality
%			column 3: the score calibrated to predict ICU mortality
%
%		OASIS_COMP	- Nx10 numeric matrix of component scores.
%		COMP_HEADER	- 1x10 cell array of strings providing the headers of 
%			each component in OASIS_COMP.
%

%	References:
%	Johnson, Alistair EW, Andrew A. Kramer, and Gari D. Clifford. "A new severity of illness scale using a subset of acute physiology and chronic health evaluation data elements shows comparable predictive accuracy*." Critical care medicine 41.7 (2013): 1711-1718.
%	

%	Copyright 2016 Alistair Johnson
%	Contact: aewj@mit.edu

% Released under the MIT license

% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
% THE SOFTWARE.

[ mdl, ranges, comp_header ] = hardcodedOASIS;

% no data input - return empty vectors
if nargin<2 || isempty(data) || isempty(header)
    oasis = [];
    oasis_comp = [];
    return;    
end
nRanges = size(ranges,2);

[N,D] = size(data);
oasis_comp = zeros(N,D);
idxOld = 0;
idxNan = isnan(data);
idxNanOASIS = false(size(idxNan));

% for each component of in all of OASIS
for r=1:nRanges
    % get the new variable index
    idxNew = ranges(2,r);
    % if the index is different, we are examining a new component variable
    if idxNew > idxOld
        % idxUnused indicates we still need to score an observation
        % since we are on a new variable, we reflags all observations for scoring
        idxUnused = true(N,1);
        idxOld = idxNew;
        
        %=== Find which column has the data associated with this variable
        idxData = strcmpi(header,comp_header{idxNew});
        if ~any(idxData)
            error('Parameter %s not found.',comp_header{idxNew});
        end
        idxNanOASIS(:,idxNew) = idxNan(:,idxData);
    end
    
    
    %=== Find data values < the current upper limit for this range
    idxAddPoints = data(:,idxData) < ranges(1,r);
    idxAddPoints = idxAddPoints & idxUnused;
    
    %=== Add OASIS score for these points to output
    oasis_comp(idxAddPoints,idxNew) = mdl(r);
    
    %=== Update these as "used" data values
    idxUnused(idxAddPoints) = false;
end

%=== Set NaNs to 0
oasis_comp(idxNanOASIS) = 0;
oasis = sum(oasis_comp,2);


%=== Predictions
oasis_pred = invlogit(-6.1746 + 0.1275 * oasis);
oasis_pred_icu = invlogit(-7.4225 + 0.1434 * oasis);

% add predictions to OASIS
oasis = [oasis, oasis_pred, oasis_pred_icu];

end


function [ mdl, ranges, lbl ] = hardcodedOASIS
% This score is stored in a custom vector format
% It matches the score published in the CCM 2013 paper

%=== the first set of elements are the ranges used to bin the data
x = [0.5;Inf; % elective surgery
    24*(0.0833333333000000)^2;24*(0.454147553000000)^2;24*(1.00017358100000)^2;24*(3.60442426957500)^2;Inf; % prelos
    24;54;65;77;90;Inf; % age
    8;14;15;Inf; % GCS
    33;87.5000000000000;106;125;Inf; % HR
    20.6500000000000;51;61.3330000000000;83.5000000000000;143.449900000000;Inf; % MAP
    6.00000000000000;13;23;31;45;Inf; % RR
    33.22;35.94;36.400;36.89;39.88;Inf; % temperature
    671.093000000000;1427;2544.14700000000;6896.80000000000;Inf; % urine output
    0.5;Inf; % ventilation
    %=== the next set of elements define the scores for the above ranges
    6;0; % elective surgery
    5;3;0;2;1; % pre-icu LOS
    0;3;6;6;9;7; % age
    10;4;3;0; % gcs 
    4;0;1;3;6; % hr
    4;3;2;0;0;3; % map
    10;1;0;1;6;9; % rr
    3;4;2;0;2;6; % temp 
    10;5;1;0;8; % urine
    0;9]; % vent
nRanges = (length(x))/2;

% create a 2xR vector
% first row is the actual ranges
% second row is an index - [1,1,2,2,...] indicates the two three components are for variable 1, etc
ranges=zeros(2,nRanges);
ranges(1,:)=x(1:nRanges);
ranges(2,:)=[0,cumsum((ranges(1,2:end)-ranges(1,1:end-1))<0)]+1;

% mdl only the scores assigned, not ranges
mdl=x(nRanges+1:end);

lbl = {'elect','PRELOS','age','gcs','hr','map','rr','temp','urine','vent'};

end
