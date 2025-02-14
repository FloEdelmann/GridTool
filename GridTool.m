%% GridTool - V1.7
% ABSTRACT
% This skript uses map data downloaded from the open street map project, 
% imports it to matlab, processes, visualizes and cleans up the data and 
% exports Excel files for nodes and lines. The data contains information 
% and coordinates of power lines of the electric grid of any selected country.
%
%
% INSTRUCTIONS TO IMPORT DATA
% Go to https://overpass-turbo.eu, click "Wizard" and create a search query
% like "power=line and voltage=* in Austria". The first part specifies
% overland power transmission lines, the second the voltage level ("*" means 
% that any voltage level is accepted) and the third the country.
% Click "run" and if applicable "continue anyway". If necessary, raise the
% "[timeout: xx]" limit. 
% Then export the data as "raw OSM data" by clicking on the "Export" button  
% and selecting the "download" button next to "raw OSM data". A 
% "export.json" file will be downloaded to your computer.
%
% 
% DESCRIPTION
% The ".json" file will be imported as "data_raw", all elementes will be
% seperated in "data_ways_all" and a "data_nodes_all".
% For easiser visualisations, x/y coordinates in [km] will be calculated from
% the given lat/lon coordinates, the origin will be the meanvalue of all 
% coordinates, aka "center of gravity".
% Coordinates (x/y and lat/lon) of endnodes will be added from "data_nodes_all"
% to "data_ways_all" and the length of each line will be calculated and added. 
% If a line has more than one voltage level, it will be cloned accordingly.
% The user than can select voltage levels, this data ("data_ways_selected")
% will be processed from now on.
% Lines which are short busbars in substations will be deleted and lines 
% which could be DC lines will be marked. If a line contains more than three 
% cables, it may be cloned accordingly.
% Endpoints which have the same coordinates will be fused, endpoints which are
% in a certain radii to each other will be grouped together - for each occuring
% voltage level there will be one seperate unique node (NUID), but they all
% have the same coordinates.
% All remaining valid ways will be exported in two Excel files.
% 
% 
% CREDITS
% (C) created by Lukas Frauenlob and Robert Gaugl October 2019, IEE, TU Graz
%
%
% CHANGELOG:
% V0.1 - 0.9: Creationprocess
% V1.0 - 24. 10. 2019, first shipping version
% V1.1 - November 2019 - Lukas Frauenlob -  added variable "data_singular_ways"
%        in function "my_delete_singular_ways" to plot those deleted
%        way elements in function "my_plot_ways_original" to avoid confusion
% V1.2 - November 2019 - Lukas Frauenlob - added way_length_multiplier
%        Setting, so line lenght gets multiplied by a factor prior
%        exporting to compensate for slack
% V1.3 - November 2019 - Lukas Frauenlob - added function my_calc_real_lengths()
%        which calculates the real lenghts of a line and exports it. Since
%        it takes a lot of time to compute, settings have been added.
% V1.4 - February 2020 - Robert Gaugl - added functionality to turn of 
%        Camparison plot
% V1.5 - April 2022 - Robert Gaugl - Changed name to GridTool and changed 
%        export function to only contain relevant data
% V1.6 - November 2022 - Robert Gaugl - Changed description of warnings/errors
% V1.7 - December 2022 - Robert Gaugl - Changed Inctructions to download data 
%		 from overpass-turbo to make this process clearer.
% V1.X - Bugfixes/added features, please describe them here


%==========================================================================
%% Initialization and Settings

% Initialization
close all
clc 
% clearvars -except data_raw file_name file_path voltage_levels_selected
clearvars
overallruntime = tic;


% Settings
% Two character country code, according to ISO-3166-1, of current country
export_excel_country_code = "AT";

% Set neighbourhood threshold radius to determine, how close endnodes have 
% to be together to get grouped
neighbourhood_threshold = 0.5;

% Max. length of a line which can be a type 'busbar', in km
busbar_max_length = 1;

% Multiplier factor for the exported length of line (slack compensation)
way_length_multiplier = 1.2;

% Display all numbers (up to 15 digits) in console without scientific notation
format long


% Calculating real line length?
% Set if the real line length should be calculated (may take some minutes) or
% the beeline ("Luftlinie") should be used
bool.calculate_real_line_length = true;

% If real line length gets visualized, set treshhold to plot only ways which
% have a difference in beeline-length/real-length of at least x% (standard: 5%)
bool.beeline_visu_treshold_diff_percent = 5;

% If real line length gets visualized, set treshhold to plot only ways which
% have a difference in beeline-length/real-length of at least xkm (standard: 0.5km)
bool.beeline_visu_treshold_diff_absolut = 0.5;


% Toogle visualisations on/off

%%% Recommended visualisations
% Visualize all selected ways, hence the original dataset 
bool.plot_ways_original = true;

% Visualize all selected ways, while they are being grouped. This plot
% includes the original and the new ways, including the threshold-circles
bool.plot_ways_grouping = true;

% Visualize all selected ways on map, final dataset with endnodes grouped
bool.plot_ways_final = true;

% Visualize distances between all endnodes to easier set neighbourhood_treshold
bool.histogram_distances_between_endpoints = false;

% Visualize Comparison between real line course and beeline
bool.plot_comparison_real_beeline = true;


%%% Optional visualisations, for debugging purposes and in-depth-research
% Visualize length of busbars to set busbar_max_length
bool.histogram_length_busbars = false;

% Visualize how many endnodes are stacked on top of each other
bool.histogram_stacked_endnodes = false;

% Visualize all stacked endnodes on map
bool.plot_stacked_endnodes = false;

% Visualize how many neighouring endnodes are grouped together 
bool.histogram_neighbouring_endnodes = false;

% visualize all neighbouring endnodes on map
bool.plot_neighbouring_endnodes = false;

    
%==========================================================================
%% Main Program
% Print welcome message and a few settings
if bool.calculate_real_line_length
    string_real_length = 'Real line length WILL be calculated';
else
    string_real_length = 'Real line length NOT be calculated';
end

fprintf(['WELCOME to GridTool! \n' ...
         '(C) created by Lukas Frauenlob and Robert Gaugl, IEE, TU Graz ' ...
         '\n\n\n--- Info ---\n' ...
         '   ... to restart data import, please delete variable ' ...
                 '"data_raw". \n' ...
         '   ... to restart voltage level selection, delete ' ...
                 '"voltage_levels_selected". \n' ...
         '   ... please check if visualisations are toggled on/off for ' ...
                 'either \n' ...
         '       performance improvements or additional information!\n\n\n' ...
         '--- Settings --- \n' ...
         '   ... Country code for Excel output: "%s" \n' ...
         '   ... Neighbouring (=grouping circle) threshold: %5.2f km \n' ...
         '   ... %s \n' ...
         '   ... Line length slack compensation factor: %3.2f' ...
         '\n\n\n'], export_excel_country_code, neighbourhood_threshold, ...
         string_real_length, way_length_multiplier)
clear string_real_length;
     

%%% Import Data
fprintf('--- Import data (Step 1/6) --- \n')

% If data wasn't imported yet, open UI, select json.file and import it
if not(exist('data_raw', 'var'))
    [data_raw, file_name, file_path] = my_import_json();
    
    % When importing new data (possibly from another country), 
    % delete old voltage_levels_selected to force new vlevel selection 
    clearvars voltage_levels_selected
end

% Separate all 'node' and 'way' elements to seperate variables and add UID
[data_nodes_all, data_ways_all] ...
    = my_seperate_raw_data_add_UID(data_raw);

% Add the lat/lon & X/Y coordinates and way lengths to all ways
[data_ways_all, degrees_to_km_conversion] ...
    = my_add_coordinates(data_ways_all, data_nodes_all);


%%% Select voltage levels
fprintf('\n--- Select voltage levels (Step 2/6) --- \n')

% Count the number of lines with a specific voltage level, display and add it 
[data_ways_all, voltage_levels_sorted] ...
    = my_count_voltage_levels(data_ways_all);
                                                                    
% Open a dialog to ask the user to select voltage levels 
if not(exist('voltage_levels_selected', 'var'))
    voltage_levels_selected ...
        = my_ask_voltage_levels(voltage_levels_sorted);
end

% Save all ways which match selected voltage levels
data_ways_selected ...
    = my_select_ways(data_ways_all, voltage_levels_selected);

                 
                 
%%% Analyse data
fprintf('\n--- Analyse data (Step 3/6) --- \n')

% Find all ways with type busbars, extract them and delete them
[data_ways_selected, data_busbars] ...
    = my_delete_busbars(data_ways_selected, bool, busbar_max_length);
                 
% Detect all possible DC lines
[data_ways_selected, dc_candidates] ...
    = my_count_possible_dc(data_ways_selected);

% Count how many cables a way has (needed to double or triple a way), add flags
data_ways_selected ...
    = my_count_cables(data_ways_selected);


%%% Group nodes
fprintf('\n--- Group nodes (Step 4/6) --- \n')

% Calculate distances between all endpoints
distances_between_nodes ...
    = my_calc_distances_between_endpoints(data_ways_selected, ...
                                          degrees_to_km_conversion, bool);

% Calculate all stacked nodes
[data_ways_selected, nodes_stacked_pairs] ...
    = my_calc_stacked_endnodes(data_ways_selected, distances_between_nodes, ...
                               bool);

% Calculate neighbouring nodes
[data_ways_selected, nodes_neighbouring_pairs] ...
    = my_calc_neighbouring_endnodes(data_ways_selected, ...
                                    distances_between_nodes, ...
                                    neighbourhood_threshold, bool);
% Group stacked nodes
nodes_stacked_grouped ...
    = my_group_nodes(nodes_stacked_pairs);

% Group neighbouring nodes                               
nodes_neighbouring_grouped ...
    = my_group_nodes(nodes_neighbouring_pairs);

% Add coordinates of stacked endnodes
data_ways_selected ...
    = my_group_stacked_endnodes(data_ways_selected, nodes_stacked_grouped);

% Add coordinates of neighbouring endnodes
[data_ways_selected, grouped_xy_coordinates] ...
    = my_group_neighbouring_endnodes(data_ways_selected, ...
                                     nodes_neighbouring_grouped, ...
                                     degrees_to_km_conversion);

% Add final coordinates, hence select from original or grouped coordinates                         
data_ways_selected ...
    = my_add_final_coordinates(data_ways_selected);
                                        
                                 
                                 
%%% Export   
fprintf('\n--- Export (Step 5/6) ---\n')

% Delete ways which have identical endpoints
[data_ways_selected, data_singular_ways] ...
    = my_delete_singular_ways(data_ways_selected);

% Calculate the real length of a line
[data_ways_selected, data_ways_selected_lengths] ...
    = my_calc_real_lengths(data_ways_selected, data_ways_all, ...
                           data_nodes_all, bool);

% Copy all tags of all ways into a seperate variable
data_ways_selected_tags ...
    = my_get_tags(data_ways_selected);

% Add LtgsID and duplicate ways if necessary
data_ways_selected ...
    = my_add_LtgsID_clone_ways(data_ways_selected, export_excel_country_code);
                                  
% Export data to excel files, add NUID
data_ways_selected ...
    = my_export_excel(data_ways_selected, export_excel_country_code, ...
                      data_ways_selected_tags, way_length_multiplier);

                  

%%% Visualisations
fprintf('\n--- Visualisations (Step 6/6) ---\n')

% Plot original ways
my_plot_ways_original(data_ways_selected, data_busbars, ...
                     voltage_levels_selected, bool, data_singular_ways);

% Plot ways while grouping endnodes
my_plot_ways_grouping(data_ways_selected, data_busbars, ...
                      grouped_xy_coordinates, neighbourhood_threshold, bool);

% Plot final ways
my_plot_ways_final(data_ways_selected, voltage_levels_selected, bool);


fprintf(['\n\nOverall runtime of program: %f seconds. \n' ... 
         'CONVERSION COMPLETED \n \n'], toc(overallruntime))
clear overallruntime        


%==========================================================================
%% Import Data
function [data_raw, file_name, file_path] ...
	= my_import_json()

    % DESCRIPTION
    % This function opens an UI to select a *.json file. With the given
    % file name and file path the *.json file will be converted to a cell
    % object. Unnecessary header files, which will be created by overpass,
    % will be deleted. 
    % 
    % INPUT
    % (none)
    %
    % OUTPUT
    % data_raw ... all data from the imported *.json file as cell array
    % file_name ... name of file
    % file_path ... path of file
    
    
    disp('Start importing Data (*.json file)...')
    
    % Open UI to select file
    [file_name, file_path] = uigetfile('*.json');
    tic
    
    % Print file path and filename to console
    fprintf('   ... file path: %s \n   ... file name: %s \n', ...
            file_path, file_name)
            
    % Import and decode selected .json file into workspace
    data_raw_jasonimport = jsondecode(fileread([file_path, file_name]));
    
    % Strip unnecessary header data from export file,  keep relevant elements
    data_raw = data_raw_jasonimport.elements;

    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)    
end

function [data_nodes_all, data_ways_all] ...
	= my_seperate_raw_data_add_UID(data_raw)

    % DESCRIPTION
    % This function importes the raw data, looks for 'node' and 'way' elements
    % and seperates them from raw data to save them in seperate variables
    % with type "struct array". If the data exported from OSM has corrupted 
    % elements (hence, a field like "tags" is missing), this element will be 
    % ignored. A manual review of the *.json file will then be necessary.
    % An unique identifier number (UID) will be created and added to 
    % every way element.
    %
    % INPUT
    % data_raw ... imported json data as cell array
    %
    % OUTPUT
    % data_nodes_all ... all node elements as struct array
    % data_way_all ... all way elements as struct array
    
    tic
    disp(['Start seperating raw data into way- ' ...
           'and node-elements... (takes a few seconds)'])
    
    % preallocation of counter variables
    num_node_elements = 0;
    num_way_elements = 0;
    
    % Seperate nodes and ways elements from raw data
    for i_raw_element = 1 : numel(data_raw)      
        
        % check if current element is a node element
        if strcmp(data_raw{i_raw_element, 1}.type, 'node')
            
              % increase node-counter
              num_node_elements = num_node_elements + 1;    
              
              % copy it to "data_nodes"
              data_nodes_cell{num_node_elements, 1} ...
                  = data_raw{i_raw_element, 1};   
               
        % check if element is a way-element   
        elseif strcmp(data_raw{i_raw_element, 1}.type, 'way') 
            
            % increase ways-counter
            num_way_elements = num_way_elements + 1;
            
            % copy it to "data_ways"
            data_ways_cell{num_way_elements, 1} = data_raw{i_raw_element, 1};
        end
    end
    
    % Try to convert the two cell variables to struct variables
    try
        % Convert from class cell to struct
        data_ways_all = cell2mat(data_ways_cell);
        data_nodes_all = cell2mat(data_nodes_cell);     
        
    % if error (fields dont match) remove structs which have more/less fields    
    catch
       
        % Count number of fields for each struct in data_ways_cell
        % and save it in a lookup table
        for i_ways_cell = 1 : numel(data_ways_cell)
            num_of_fields_ways(i_ways_cell) ...
                = numel(fieldnames(data_ways_cell{i_ways_cell})');       
        end

        % Count number of fields per struct in data_nodes_cell
        % and save it in a lookup table
        for i_nodes_cell = 1 : numel(data_nodes_cell)
            num_of_fields_nodes(i_nodes_cell) ...
                = numel(fieldnames(data_nodes_cell{i_nodes_cell})');       
        end

        % create boolean index, which fields have "average" number of fields
        b_num_of_fields_ok_ways ...
            = num_of_fields_ways == median(num_of_fields_ways);
        b_num_of_fields_ok_nodes ...
            = num_of_fields_nodes == median(num_of_fields_nodes);

        % If at least one field is not ok, hence has more or less fields
        if any(not(b_num_of_fields_ok_ways))

            % Print error message
            fprintf(['   ATTENTION! There is at least one way element which'...
                     ' has a different amount of fields. \n              ' ...
                     'It wont be imported! \n'])

            % delete all these elements and continue
            data_ways_cell = data_ways_cell(b_num_of_fields_ok_ways);
        end
        
        % Do the same with nodes    
        if any(not(b_num_of_fields_ok_nodes))

            % Print error message
            fprintf(['   ATTENTION! There is at least one node element which'...
                     ' has a different amount of fields. \n              ' ...
                     'It wont be imported! \n'])

            % delete all these elements and continue
            data_nodes_cell = data_nodes_cell(b_num_of_fields_ok_nodes);
        end
        
        % Convert from class cell to struct
        data_ways_all = cell2mat(data_ways_cell);
        data_nodes_all = cell2mat(data_nodes_cell);          
    end
    
    % Create unique ID (UID) and add it
    for i_way_element = 1 : numel(data_ways_all)
        data_ways_all(i_way_element).UID = i_way_element;
    end

    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end

function [data, degrees_to_km_conversion] ...
	= my_add_coordinates(data, data_nodes_all)

    % DESCRIPTION
    % The first and last node IDs, hence the endpoints, will be extracted 
    % from every way element and the correspondending lon/lat coordinates
    % will be added to every way element. Since lon/lat coordniates don't
    % give an intutive feeling of distances in a plot, x/y coordnates in km
    % will be calculated. This will be done by a rough (but sufficient)
    % approximation: The midpoint (COG - center of gravity) of all lon/lat
    % coordinates will be calculated and will be the 0-origin of the x/y plane.
    % An approxmation formula calculates the km-per-degree-conversion on this 
    % point on earth. From every endpoint the latitudinal/longitudinal distance 
    % to the midpoint will be converted to the x/y km distance, this x/y
    % value will be added to every way element. Using that information, 
    % the distance between the endpoints will be calculated and added too.
    %
    % INPUT
    % data ... dataset off all way elements
    % data_nodes_all ... dataset of all node elements
    %
    % OUTPUT
    % data ... the updated dataset off all way elements: IDs of endnodes, 
    %          lat/lon coordinates, x/y coordinates, length of line
    % degrees_to_km_conversion ... the necessary information to convert lon/lat
    %                              to x/y coordinates for further use of
    %                              grouped endnodes in another function.
    
    tic
    disp('Start adding coordinates to each way... (takes a few seconds)')

    % Create a list of all node ids
    list_all_node_IDs = [data_nodes_all(:).id]';
  
    % Add all endnode coordinates to data
    for i_ways = 1 : numel(data)
        
        % Add first and last endnode IDs as seperate elements to data
        data(i_ways).ID_node1 = data(i_ways).nodes(1, 1);
        data(i_ways).ID_node2 = data(i_ways).nodes(end, 1);
        
        % Find the position of the endnode id in thelist_all_node_IDs
        position_node1 = find(data(i_ways).ID_node1 == list_all_node_IDs, 1);
        position_node2 = find(data(i_ways).ID_node2 == list_all_node_IDs, 1);
                              
        % use this position to assign the lon/lat coordinates to data_ways                      
        data(i_ways).lon1 = data_nodes_all(position_node1).lon;
        data(i_ways).lat1 = data_nodes_all(position_node1).lat;
        data(i_ways).lon2 = data_nodes_all(position_node2).lon;
        data(i_ways).lat2 = data_nodes_all(position_node2).lat;             
    end
     
    % Calculate latitudinal/longitudinal midpoint of all coordinates
    mean_lat = mean([[data.lat1], [data.lat2]]);
    mean_lon = mean([[data.lon1], [data.lon2]]);   
    
    % Determine if we are on North/South Hemisphere ...
    if mean_lat > 0
        fprintf('   INFO: Majority of nodes are on the NORTH and ')
    else
        fprintf('   INFO: Majority of nodes are on the SOUTH and ')
    end
    
    % ... and East/West Hemisphere, then print this information to console
    if mean_lon > 0
        fprintf('EASTERN hemisphere \n')
    else
        fprintf('WESTERN hemisphere \n')
    end 
    
    disp('   ... start calculating and adding x/y coordinates...')
    
    % at this mean position, calculate how many km approx. equal one degree
    % source: https://gis.stackexchange.com/questions/75528/...
    %         understanding-terms-in-length-of-degree-formula/75535#75535
    
    radians = mean_lat * pi / 180;
 
    km_per_lon_deg = (111132.954 * cos(1 * radians) ...
                         - 93.55 * cos(3 * radians) ...
                         + 0.118 * cos(5 * radians)) / 1000; 
                   
    km_per_lat_deg = (111132.92 ...
                       - 559.82 * cos(2 * radians) ...
                       +  1.175 * cos(4 * radians) ...
                       - 0.0023 * cos(6 * radians)) / 1000;                                     

    % calculate the difference in degree for each point from midpoint
    delta_lon1 = [data.lon1]' - mean_lon;
    delta_lon2 = [data.lon2]' - mean_lon;      
    delta_lat1 = [data.lat1]' - mean_lat;
    delta_lat2 = [data.lat2]' - mean_lat;
    
    % convert the delta_degree into delta_kilometer, as x1/x2/y1/y2
    x1 = delta_lon1 * km_per_lon_deg;
    x2 = delta_lon2 * km_per_lon_deg;
    y1 = delta_lat1 * km_per_lat_deg;
    y2 = delta_lat2 * km_per_lat_deg;   
    
    % convert the delta_kilometer into cell arrays to process them in batch
    x1_cell = num2cell(x1);
    x2_cell = num2cell(x2);
    y1_cell = num2cell(y1);
    y2_cell = num2cell(y2); 
    
    % save delta_kilometer to data_ways
    [data.x1] = x1_cell{:};
    [data.y1] = y1_cell{:};
    [data.x2] = x2_cell{:};
    [data.y2] = y2_cell{:};
    
    disp('   ... calculate length of each line and add it...')
        
    % Calculate distances between endpoints and add it
    length = num2cell(sqrt((x1 - x2).^2 + (y1 - y2).^2)');
    [data.length] = length{:};
    
    % Return the conversion data to use it later again for grouped nodes              
    degrees_to_km_conversion = [km_per_lon_deg, km_per_lat_deg, ...
                                mean_lon, mean_lat];
        
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)
end


%==========================================================================
%% Select voltage levels
function [data, voltage_levels_unique] ...
	= my_count_voltage_levels(data)

    % DESCRIPTION
    % This function reads the tag information about the voltage level and 
    % adds that information to every way element. If a way has two or three
    % different voltage levels, the corresponding way will be
    % doubled/tripled automatically. A list of all voltage levels will be
    % displayed to the console.
    %
    % INPUT
    % data ... dataset of all way elements
    %
    % OUTPUT
    % data ... updated dataset off all way elements: ways with multiple 
    %          voltage levels got cloned and "number of voltage levels" and
    %          the volage level got added to every way element
    % voltage_levels_unique ... a list of all voltage levels in the dataset

    
    tic
    disp('Start counting voltage levels...')
       
    %%% Extract all voltage levels and add them to every way element
    for i_ways = 1 : numel(data)
        
        % Check if there is even a voltage field
        if not(isfield(data(i_ways).tags, 'voltage'))
            % print warning to console
            fprintf(['   ATTENTION! Way element UID %d does not ' ...
                     'contain a field "voltage". This way wont be selected. \n'], ...
                     data(i_ways).UID)
                  
            % cancel that element, skip rest of for-loop, go to next i_ways
            continue
        end
        
        % clear voltage level variable (error if old values are still there)
        voltage_levels = [];

        % save the voltage in temporary variable     
        voltage_levels = str2double(data(i_ways).tags.voltage);
        
        % If there is more than one voltage level, check if there are two 
        if isnan(voltage_levels)
            
            % Split the two voltage levels, sperated by ";", up
            voltage_levels ...
                = str2double(strsplit(data(i_ways).tags.voltage, ';'));
        end
          
        % if there is still an invalid voltage level, print a message to
        % console and skip that element
        if any(isnan(voltage_levels))
            
            % print warning to console
            fprintf(['   ATTENTION! UNKNOWN voltage level ("%s") ' ...
                     'in UID %d. This way wont be selected. \n'], ...
                      data(i_ways).tags.voltage, data(i_ways).UID)
                  
            % cancel that element, skip rest of for-loop, go to next i_ways
            continue
        end
        
        % if it's just one voltage level, add voltage level to curr. way
        if numel(voltage_levels) == 1
            
            data(i_ways).voltage = voltage_levels;    
            data(i_ways).vlevels = 1;
                   
        % if there are two voltage levels, add flag and print to console
        elseif numel(voltage_levels) == 2
            
            data(i_ways).voltage = []; 
            data(i_ways).vlevels = 2;
            fprintf(['   ATTENTION! Two voltage levels ("%s") ' ...
                     'in UID %d. This way will be duplicated. \n'], ...
                      data(i_ways).tags.voltage, data(i_ways).UID)            
        
        % if there are three voltage levels, add flag and print to console           
        elseif numel(voltage_levels) == 3
                        
            data(i_ways).voltage = [];
            data(i_ways).vlevels = 3;      
            fprintf(['   ATTENTION! Three voltage levels ("%s") ' ...
                     'in UID %d. This way will be tripled. \n'], ...
                      data(i_ways).tags.voltage, data(i_ways).UID)
                  
        % if there is not voltage level entry at all, print message to console            
        else
            data(i_ways).voltage = [];
            data(i_ways).vlevels = [];  
            fprintf(['   ATTENTION! Unkown voltage levels ("%s") ' ...
                     'in UID %d. This way wont be selected. \n'], ...
                      data(i_ways).tags.voltage, data(i_ways).UID)                  
        end
    end
    

    %%% Clone ways with two or three different voltage levels
    fprintf(['\n   ... start cloning lines with multiple voltage levels... ' ...
             '(may take a few seconds) \n'])
         
    % Initialize counter variables
    num_of_cloned_ways = 0;
    iterations_to_skip = 0;
    
    % Go throuh every way element (add cloned ways to reach last way too)
    for i_ways = 1 : numel(data) + num_of_cloned_ways
    
        % Skip iterations if a way got cloned in a previous iteration
        if iterations_to_skip > 0
            
            % Skip once and decrease to_skip_counter by 1
            iterations_to_skip = iterations_to_skip - 1;
            continue;
        end
                                   
        % If there are two voltage leveles, duplicate a way
        if data(i_ways).vlevels == 2
            
            % Get the two voltage levels of current way
            voltage_levels ...
                = str2double(strsplit(data(i_ways).tags.voltage, ';'));
            
            % copy the current way two times
            way_to_clone_a = data(i_ways);
            way_to_clone_b = data(i_ways);
            
            % Add the two voltage levels to one way each
            way_to_clone_a.voltage = voltage_levels(1);
            way_to_clone_b.voltage = voltage_levels(2);
            
            % Duplicate the way
            data = [data(1 : (i_ways - 1)); ...
                    way_to_clone_a; way_to_clone_b;
                    data((i_ways + 1) : end)]; 
            
            % run the for-loop one iteration longer to reach the last way
            num_of_cloned_ways = num_of_cloned_ways + 1;
            
            % Skip next interation to ignore the cloned way
            iterations_to_skip = 1;   
        end
        
        
        % if there are three voltage levels, 
        if data(i_ways).vlevels == 3
            
            % Get the three voltage levels of current way
            voltage_levels ...
                = str2double(strsplit(data(i_ways).tags.voltage, ';'));
            
            % copy the current way three times
            way_to_clone_a = data(i_ways);
            way_to_clone_b = data(i_ways);
            way_to_clone_c = data(i_ways);
            
            % Add the three voltage levels to one way each
            way_to_clone_a.voltage = voltage_levels(1);
            way_to_clone_b.voltage = voltage_levels(2);
            way_to_clone_c.voltage = voltage_levels(3);
            
            % Triple the way
            data = [data(1 : (i_ways - 1)); ...
                    way_to_clone_a; way_to_clone_b; way_to_clone_c;
                    data((i_ways + 1) : end)];  
            
            % run the for-loop two iterations longer to reach the last way
            num_of_cloned_ways = num_of_cloned_ways + 2;
            
            % Skip the next two interation to ignore the cloned ways
            iterations_to_skip = 2;   
        end        
    end
    
    
    %%% Count all voltage levels
    % Calculate how many ways have a certain voltage level
    [voltage_levels_occurance, voltage_levels_unique] ...
            = hist([data(:).voltage], unique([data(:).voltage]));
        
    % format that information   
    voltage_levels_unique = sort(voltage_levels_unique, 'descend')';
    voltage_levels_occurance = flipud(voltage_levels_occurance');
    
    % print that information to console
    fprintf('\n')
    disp(array2table([voltage_levels_unique, voltage_levels_occurance], ...
                     'VariableNames', {'voltage_level','number_of_ways'}))
        
    % Print how many ways do not contain information about voltage             
    fprintf('   ... there are %d way(s) with unknown voltage level. \n', ...
            numel(data) - sum(voltage_levels_occurance))
    
    fprintf('   ... finished! (%5.3f seconds) \n\n' , toc)                           
end

function voltage_levels_selected ...  
	= my_ask_voltage_levels(voltage_levels_sorted)

    % DESCRIPTION
    % This function opens an UI which displays all found voltage
    % levels of the dataset. The user can select one / multiple / all
    % voltage levels, this information will be returned as list. If the user
    % cancels the dialog, all voltage levels will be selected.
    %
    % INPUT
    % voltage_levels_sorted ... a list of all unique voltage levels of dataset
    %
    % OUTPUT
    % voltage_levels_selected ... a list of all selected voltage levels
                                                    
    % Settings for the dialog
    vlevels_default = num2str(voltage_levels_sorted(:, 1));
    dialog_title = 'Voltage Level Selection';
    dialog_description = 'Plese select one or multiple voltage levels';
    dialog_window_size = [250, 300]; % matlab default: [160 300]
    
    % Create dialog to select voltagelevels
    [index_selected, b_select_ok] = listdlg('ListString', vlevels_default, ...
                                            'Name', dialog_title, ...
                                            'ListSize', dialog_window_size, ...
                                            'PromptString',dialog_description);

    % return selected voltage levels, if user made a selection
    if b_select_ok
        voltage_levels_selected = voltage_levels_sorted(index_selected, 1);
    
    % If user didn't select anything, return all voltages
    else
        voltage_levels_selected = voltage_levels_sorted(:, 1);
    end
end  

function data_ways_selected ...
    = my_select_ways(data_ways_all, vlevels_selected)

    % DESCRIPTION
    % This function copys all ways, which have a voltage level which got
    % selected, to a new structs
    %
    % INPUT
    % data_ways_all ... dataset of all ways
    % vlevels_selected ... list of selected voltage levels
    %
    % OUTPUT
    % data_ways_selected ... dataset of all ways which have a selected
    %                        voltage leve
    
    tic
    disp('Start selecting ways according to their voltage level...')
    
    % Initialize ID Counter for the new 'data_ways_selected'           
    i_ways_selected = 1;
    
    % Go through every way element of all ways
    for i_ways_org = 1 : numel(data_ways_all)
        
        % If voltage level of current way got selected
        if any(ismember(data_ways_all(i_ways_org).voltage, vlevels_selected))
            
            % copy current way to new struct
            data_ways_selected(i_ways_selected) = data_ways_all(i_ways_org);
            
            % Increase element counter of new struct
            i_ways_selected = i_ways_selected + 1;
        end
    end
   
    % Transpose the new struct to match other dimensions
    data_ways_selected = data_ways_selected';
   
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)
end


%==========================================================================
%% Analyze data
function [data, data_busbars] ...
	= my_delete_busbars(data, bool, busbar_max_length)

    % DESCRIPTION
    % This function checks if a way is declared as a busbar or bay, if so, it
    % checks if its length is less than the max treshhold and adds a flag
    % to that way element. The lenght of a busbar will be saved in a
    % seperate variable, which can optionally be plotted in a histogram to
    % set the max. busbar lenght accordingly. All busbars will be extraced to 
    % a seperate variable and then deleted from the original dataset.
    %
    % INPUT
    % data ... dataset of selected ways
    % bool ... boolean struct if the histogram should be plotted or not
    % busbar_max_length ... the maximal length a busbar can have
    %
    % OUTPUT
    % data ... updated dataset with all busbars deleted
    % data_busbars ... all way elements which are busbars
    
    tic 
    disp('Start deleting ways with type "busbar" or "bay"...')
    
    % Initialize counter for busbars
    i_busbars_bays = 0;
    
    % go through all way-elements
    for i_ways = 1 : numel(data)
        
        % Condition if the tag field "line" exists
        b_line_field_exists = isfield(data(i_ways).tags, 'line');
        
        % Condition if length of current way is less then max. busbar length
        b_length_ok = data(i_ways).length < busbar_max_length;
        
        % if "line" field exists and if it's value is "busbar" or "bay"
        if b_line_field_exists ...
            && (strcmp(data(i_ways).tags.line, 'busbar') ...
                || strcmp(data(i_ways).tags.line, 'bay'))
                
            % and if its length isn't too long
            if b_length_ok
                
                % Set flag that current way is a busbar/bay
                data(i_ways).busbar = true; 
                
                % Increase counter if found busbars or bays
                i_busbars_bays = i_busbars_bays + 1;
                
                % Save its length for an optional histogram
                lengths_of_busbars(i_busbars_bays) = data(i_ways).length; 
                
            % but if its length is too long, skip it and print message
            else
                fprintf(['   ATTENTION!  Way Element UID %d has type ' ...
                '"busbar" or "bay", but is too long. \n               ' ...
                'Length: %5.2f km of max. %3.1f km \n               ' ... 
                'This way wont be added to the ' ...
                '"busbar" exception list. \n'], ...
                data(i_ways).UID, data(i_ways).length, busbar_max_length)
                data(i_ways).busbar = false; 
            end   
        
        % If it's not a busbar nor bay...
        else
            % ... set flag accordingly    
            data(i_ways).busbar = false; 
        end
    end

    % extract all busbars/bays to a seperate variable
    data_busbars = data([data.busbar]);
   
    % delete all busbars/bays from original dataset
    data([data.busbar]) = [];
    
    % Optional: Histogram of busbar/bays lengths, to set max busbar length
    if bool.histogram_length_busbars
        figure
        histogram(lengths_of_busbars, 200)
        title('Lengths of busbars/bays below busbar-max-length-treshold')
        xlabel('Length [km]'), ylabel('Number of busbars with that length')
    end
    
    fprintf(['   ... %d busbars have been deleted\n' ...
             '   ... finished! (%5.3f seconds) \n \n'], ...
             i_busbars_bays, toc)
end

function [data, dc_candidates] ...
	= my_count_possible_dc(data)

    % DESCRIPTION
    % This function checks every way element, if it could potentially be a
    % DC line. There are three hints that a line may be a DC line: It has
    % only 1 cable, the frequency is "0" or name contains somewhere the two
    % letter "dc". If one or more of those checks are correct, the UID,
    % reason and voltage level will be copied to a seperate variable for
    % later manuell checks.
    %
    % INPUT
    % data ... the dataset of selected ways
    %
    % OUTPUT
    % data ... updated dataset, including a flag if a way may be a DC line
    % dc_candidates ... list of all UIDs which may be a DC line
   
    
    tic
    fprintf('Start detecting lines which could be DC lines... \n')

    % Initialize the DC_candidate struct
    dc_candidates(1).UID = [];

    % Go through every way element
    for i_ways = 1 : numel(data)

         % if field "frequency" exists AND its value is 0
        if isfield(data(i_ways).tags, 'frequency') ...
                && str2double(data(i_ways).tags.frequency) == 0

            % Set boolean tag 'b_candidate_dc' true
            data(i_ways).dc_candidate = true;          
           
            % Add the UID of that way
            dc_candidates(end + 1).UID = data(i_ways).UID;

            % Add voltage level of that way
            dc_candidates(end).voltage_level = data(i_ways).voltage;
            
            % Add the reason
            dc_candidates(end).reason = 'tag "frequency" has value "0"'; 
      
        else
            % Set boolean tag false (next condition may change that)
            data(i_ways).dc_candidate = false;         
        end
         
              
        % if field "name" exists AND contains the case insensitive value 'DC'
        if isfield(data(i_ways).tags, 'name') ...
               && any(strfind(lower(data(i_ways).tags.name), 'dc'))

            % Set boolean tag 'b_candidate_dc' true
            data(i_ways).dc_candidate = true;  
            
            % Add the UID of that way
            dc_candidates(end + 1).UID = data(i_ways).UID;

            % Add the reason
            dc_candidates(end).reason = 'tag "name" contains "DC"'; 
            
            % Add voltage level of that way
            dc_candidates(end).voltage_level = data(i_ways).voltage;
            
        else
             % Set boolean tag false (next condition may change that)
            data(i_ways).dc_candidate = false;   
            
        end
        
        % if field "cables" exists AND its value is 1
        if isfield(data(i_ways).tags, 'cables') ...
               && str2double(data(i_ways).tags.cables) == 1

            % Set boolean tag 'b_candidate_dc' true
            data(i_ways).dc_candidate = true;          
           
            % Add the UID of that way
            dc_candidates(end + 1).UID = data(i_ways).UID;

            % Add voltage level of that way
            dc_candidates(end).voltage_level = data(i_ways).voltage;
            
            % Add the reason
            dc_candidates(end).reason = 'tag "cables" has value "1"'; 
      
        else
            % Set boolean tag false 
            data(i_ways).dc_candidate = false;              
        end      
	end

    % Delete the first (and empty) entry of that cable struct
    dc_candidates(1) = []; 

    % Output information depending if candidates were found or not
    if size(dc_candidates, 2) == 0
        
        % Add information to variable
        dc_candidates(1).UID = ['No possible DC candidate in all ways of ' ...
                                'those selected voltage levels found!'];
                                              
        % Print information to console
        disp('   ... no potentially DC lines found.')            
                        
    else
        % Print how many ways do not contain information about cables             
        fprintf(['   ... %d ways could pontentially be a DC line.  \n' ...
                 '   ... Please refer in workspace to variable DC ' ...
                         'candidates \n ' ...
                 'to manually check them if necessary! \n'], ...
                 numel(unique([dc_candidates(:).UID])))
    end

    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end

function data ...
	= my_count_cables(data)

    % DESCRIPTION
    % This function checks for every way element the number of cables, adds
    % them to the dataset and to a sepearte variable "cabels_per_way". If a
    % line obviously carries 2, 3 or 4 systems, a flag will be set
    % accordingly and that way will be doubled, tripled or quadrupled in a
    % later function.
    %
    % INPUT
    % data ... dataset of selected ways
    %
    % OUTPUT
    % data ... updated dataset with new fields "num_of_cables" and "systems"
    
    
    tic
    fprintf('Start counting cables per way... \n')

    % Initialize the cables struct
    cables_per_way(1).UID = [];

    % Go through every way
    for i_ways = 1 : numel(data)        

         % check if "cable" field even exists
         if isfield(data(i_ways).tags, 'cables')
            
            % Some ways have different number of cables for different voltage
            % levels, catch that NaN error, if a cable is for example "3;6".
            if isnan(str2double(data(i_ways).tags.cables))
                fprintf(['   ATTENTION! Unknown cable number ("%s") in ' ...
                         'UID %d. This way wont be cloned ' ... 
                         'automatically.\n'], ...
                         data(i_ways).tags.cables, data(i_ways).UID);
                continue;
            end

            % Add the UID of that way
            cables_per_way(end + 1).UID = data(i_ways).UID;
            
            % Add the number of cables as field to dataset
            data(i_ways).cables = str2double(data(i_ways).tags.cables);
            
            % Add the number of cables of that way to a seperate variable
            cables_per_way(end).num_of_cables ...
                = str2double(data(i_ways).tags.cables);
            
            % If it's a double system (2x3 cables), set flag accordingly
            if cables_per_way(end).num_of_cables == 6
                data(i_ways).systems = 2;

            %If it's a triple system (3x3 cables), set flag accordingly
            elseif cables_per_way(end).num_of_cables == 9
                data(i_ways).systems = 3;   
                
            % if it's a quadruple system (4x3 cables), set flag accordingly
            elseif cables_per_way(end).num_of_cables == 12
                data(i_ways).systems = 4;    
                
            % if none of the above, leave it empty
            else
                data(i_ways).systems = [];    
            end 
            
         % there is no information regarding cable number
         else
             % leave flag empty
             data(i_ways).systems = [];    
         end
    end

    % Delete the first (and empty) entry of that cable struct
    cables_per_way(1) = []; 

    if size(cables_per_way, 2) == 0
        % Print that in this selection no cables per way info was found
        fprintf(['   ... the ways in this voltage level selection \n     ' ...
                 '   dont provide information about number of cables...\n'])
             
        % Save that information in output variable too
        cables_per_way(1).UID = ['   ... the ways in this voltage level ' ...
                                 'selection dont provide any information ' ...
                                 'about number of cables! \n'];       
             
    else
        % Calculate how many ways have a certain cable count
        [cables_occurance, cables_unique] ...
            = hist([cables_per_way.num_of_cables], ...
                   unique([cables_per_way.num_of_cables]));

        % print that information to console
        fprintf('\n')
        disp(array2table([cables_unique', cables_occurance'], ...
                        'VariableNames', {'cables_per_way', 'number_of_ways'}))

        % Print how many ways do not contain information about cables             
        fprintf('   ... %d ways with unknown number of cables. \n', ...
                numel(data) - sum(cables_occurance))

        % Print little explanation to console
        fprintf(['   ... ways with 6 cables will be doubled, ways with 9 ' ...
                 'cables tripeled \n       and ways with 12 cables ' ...
                 'quardupled.\n   ... Please refer in workspace to '...
                 'variable "cables_per_way"   \n       to manually check ' ...
                 'other ways (DC? Traction Current? Unused cable?) ' ...
                 'if necessary. \n'])
    end
    
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end


%==========================================================================
%% Group nodes
function M ...
	= my_calc_distances_between_endpoints(data, degrees_to_km_conversion, bool)

    % DESCRIPTION
    % This function creates a Matrix "M" or "distances" whith all distances
    % between all endpoints. "M" would be a diagonal symmetrical Matrix
    % (distances A to B is equal to distances B to A), so all elements in
    % the south-west diagonal half will be set to "NaN". Distances
    % between the same element (distance A to A or B to B) will be set to
    % "-1" since this is an impossible distance value and therefore
    % distinguishable. The correct value would be "0", but since we are
    % looking speficially for stacked endnodes (distance A to B equals 0)
    % the true value ("0") will not be used. Optionally a histogram of all
    % distances can be plotted - this can be very useful to set the
    % neighbouring threshold value.
    %
    % INPUT
    % data ... dataset of all selected ways
    % bool ... boolean selector to optionally plot a histogram.
    %
    % OUTPUT
    % M ... matrix with all distances between all endpoints
    
    
    tic
    disp(['Start calculating distances between all endpoints' ...
          '... (takes a few seconds)'])
    
    % preallocate the distance matrix with NaN-elements
    M = NaN(numel(data)*2);

    % Extract degrees to km conversion data into variables
    km_per_lon_deg = degrees_to_km_conversion(1); 
    km_per_lat_deg = degrees_to_km_conversion(2);                  

    % Fetch coordinates for the horizontal row which contains
    % every 4x4 block of endnodes.
    all_lon1 = [data(1:end).lon1];
    all_lon2 = [data(1:end).lon2];
    all_lat1 = [data(1:end).lat1];
    all_lat2 = [data(1:end).lat2];
        
    % go through each row of distance matrix
    for i_row = 1 : numel(data)
        
        % Initialize variables, delete old values before each iteration
            % naming scheme of variables:
            % lat_deltas... = all latitudinal deltas to the values of data_row
            % lon_deltas... = all longitudinal deltas to the values of data_row
            % ...to_xxxx... = refering to lon1/lat1/lon1/lon2 of data_column
            % ...deg/km = value in degrees or in x/y km
        lon_deltas_to_lon1_deg = [];
        lon_deltas_to_lon2_deg = [];
        lat_deltas_to_lat1_deg = [];
        lat_deltas_to_lat2_deg = [];  
        lon_deltas_to_lon1_km = [];
        lon_deltas_to_lon2_km = [];
        lat_deltas_to_lat1_km = [];
        lat_deltas_to_lat2_km = [];

        % Create the 4x4 field of the current row, which will calculate
        % distances to all other endnodes
        data_column = [data(i_row).lon1, data(i_row).lat1; ...
                       data(i_row).lon2, data(i_row).lat2];

        % Every iteration this row gets smaller by one 4x4 block. Therefore
        % delete the first coordinates from previous run
        all_lon1 = all_lon1(2:end);
        all_lon2 = all_lon2(2:end);
        all_lat1 = all_lat1(2:end);
        all_lat2 = all_lat2(2:end);

        % Preallocate the row vector
        data_row = zeros(2, numel(all_lon1) * 2);

        % Copy all coordinates in alternating order to the row
        data_row(1, 1:2:end) = all_lon1(1:end);
        data_row(1, 2:2:end) = all_lon2(1:end);
        data_row(2, 1:2:end) = all_lat1(1:end); 
        data_row(2, 2:2:end) = all_lat2(1:end); 

        % Calc absolute distance in degree between lon/lat coordinates    
        lon_deltas_to_lon1_deg = data_column(1) - data_row(1:2:end);
        lon_deltas_to_lon2_deg = data_column(2) - data_row(1:2:end);
        lat_deltas_to_lat1_deg = data_column(3) - data_row(2:2:end);
        lat_deltas_to_lat2_deg = data_column(4) - data_row(2:2:end);

        % Convert the delta_degree to delta_kilometer    
        lon_deltas_to_lon1_km = lon_deltas_to_lon1_deg * km_per_lon_deg;
        lon_deltas_to_lon2_km = lon_deltas_to_lon2_deg * km_per_lon_deg;
        lat_deltas_to_lat1_km = lat_deltas_to_lat1_deg * km_per_lat_deg;
        lat_deltas_to_lat2_km = lat_deltas_to_lat2_deg * km_per_lat_deg;

        % Use Pythagoras to calculate distances between endpoints
        M_new_row = [];
        M_new_row(1, :) ...
            = sqrt(lon_deltas_to_lon1_km.^2 + lat_deltas_to_lat1_km.^2);
        M_new_row(2, :) ...
            = sqrt(lon_deltas_to_lon2_km.^2 + lat_deltas_to_lat2_km.^2);
        
        % Apply the newly calculated distance row to the distance matrix
        M([i_row*2 - 1, i_row*2], i_row*2 - 1 : end) = [-ones(2), M_new_row];                      
    end
    
    % Plot a Histogram of all the distances 
    if bool.histogram_distances_between_endpoints
        disp('   ... start visualizing all distances in a histogram ...')
   
        h = figure;
        % Set windows size double the standard length
        set(gcf, 'Position', [h.Position(1:3), h.Position(4) * 2])
        
        subplot(5,1,1)
        histogram(M, 200, 'BinLimits', [0, max(max(M))])
        title('Distances between all endnodes')
        ylabel('number of pairs'), xlabel('distance [km]')

        subplot(5,1,2)
        histogram(M, 200, 'BinLimits', [0, 10])
        ylabel('number of pairs'), xlabel('distance [km]')

        subplot(5,1,3)
        histogram(M, 400, 'BinLimits', [-1.5, 2])
        ylabel('number of pairs'), xlabel('distance [km]')

        subplot(5,1,4)
        histogram(M, 300, 'BinLimits', [0, 0.3])
        ylabel('number of pairs'), xlabel('distance [km]')
        
        subplot(5,1,5)
        histogram(M, 300, 'BinLimits', [0 + eps, 0.3])
        ylabel('number of pairs'), xlabel('distance [km]')
    end    
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)
end

function [data, nodes_stacked_pairs] ...
	= my_calc_stacked_endnodes(data, distances, bool)

    % DESCRIPTION
    % This function searches every distance combination between all
    % endpoints which have the value "0", which means that two endpoints
    % have the same coordinates and are stacked on top of each other. (This
    % is easy to do and drastically increases computing performance in
    % upcoming functions). Since in the distance Matrix M every endnode
    % needs two rows/columns, the original "ID" will be recalculate to get
    % the right way element. To the dataset a boolean flag will be added to
    % determine if endnode1/2 is stacked. A list of all pairs of stacked
    % endnodes will be return for further grouping. Optionally data of all
    % stacked endnodes can be plotted and also a histogram of how many
    % endnodes are stacked can be shown.
    %
    % INPUT
    % data ... input dataset
    % distances ... distance Matrix M which contains distances between all
    %               endnodes
    % bool ... boolean selector variable to toogle on/off the visualisations
    %
    % OUTPUT
    % data ... updated dataset, new flag: endnode1/2_stacked
    % nodes_stacked_pairs ... a raw list of all pairs of stacked endnodes
    
    tic
    disp('Start finding all stacked endnodes...')
    
    %%% Get the way ids of stacked elements
    % Create boolean logical index of all distance combinations witch equal 0
    b_dist_is_zero = distances == 0;
    
    % if no distance element has value 0, cancel that function since no two
    % endpoints are stacked
    if not(any(any(b_dist_is_zero)))
        
        % Set all boolean flags to false
        [data(:).node1_stacked] = deal(false);
        [data(:).node2_stacked] = deal(false);
         
        % Create empty pseudo output
        nodes_stacked_pairs = [];
        
        % Print this information to console
        fprintf('   ... no endnode is stacked! \n')
        
        % End that function
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
        return
    end
    
    % Get the indices of this boolean matrix, hence the row/column IDs
    [nodes_stacked_indices.raw_column, nodes_stacked_indices.raw_row] ...
        = find(b_dist_is_zero);
    
    % Combine the row(y)- and column(x)-indices in one list and sort them
    nodes_stacked_indices.raw_combined ...
        = sort([nodes_stacked_indices.raw_column; ...
                nodes_stacked_indices.raw_row]);
        
    % remove duplicates: extract unique ids and calculate their occurances
    [nodes_stacked_indices.unique_occurance, nodes_stacked_indices.unique] ...
        = hist(nodes_stacked_indices.raw_combined, ...
               unique(nodes_stacked_indices.raw_combined));
           
    % match dimensions, hence transpose "unique_occurance"       
    nodes_stacked_indices.unique_occurance ...
        = nodes_stacked_indices.unique_occurance';
    
    fprintf('   ... %d endnodes are stacked! \n', ...
        size(nodes_stacked_indices.unique, 1))
    
    % Create new table, first column: unique indices
    nodes_stacked = table(nodes_stacked_indices.unique, ...
                          'VariableNames', {'index'});

    % Convert indices to Wayelement ID               
    nodes_stacked.way_ID = ceil(nodes_stacked.index / 2);   
   
    % Convert indices to boolean indicator if it's endnode1 (true) or 2 (false)
    nodes_stacked.endnode1 = mod(nodes_stacked.index, 2);
 
    % return all pairs, to group them later in another function      
    nodes_stacked_pairs ...
        = [nodes_stacked_indices.raw_row, nodes_stacked_indices.raw_column];
    
    
    %%% Add stacked information to dataset
    % Start with first index
    i_stacked_nodes = 1;
    
    % Initialize frequent used variabel
    numel_way_IDs = numel(nodes_stacked.way_ID);
    
    % go through all ways in data_ways_selected
    for i_ways = 1 : size(data, 1)

        % Catch out-of-index-error if very last index (last way, endnode 2)
        % is stacked: Then break the loop
        if i_stacked_nodes > size(nodes_stacked, 1)
            
            % change variable so the next if check fails
            i_stacked_nodes = i_stacked_nodes - 1;
        end
        
        % Does current way (from data_ways_selected) contain a stacked endnode? 
        if i_ways == nodes_stacked.way_ID(i_stacked_nodes)
        % Yes, at least one endnode is stacked
            
            % Are both endnodes stacked?
            % Check if it's not the last way_ID AND next way_ID is identical
            if (i_stacked_nodes < numel_way_IDs) ...
                    && ((nodes_stacked.way_ID(i_stacked_nodes) ...
                         == nodes_stacked.way_ID(i_stacked_nodes + 1)))
            
                % Yes, both endnodes are stacked
                data(i_ways).node1_stacked = true;
                data(i_ways).node2_stacked = true;

                % Skip one index, since we just set two nodes
                i_stacked_nodes = i_stacked_nodes + 1; 
               
            % No, not both. So only one. Is endnode 1 stacked?  
            elseif nodes_stacked.endnode1(i_stacked_nodes)
                
                % Yes, endnode 1 is stacked
                data(i_ways).node1_stacked = true;
                data(i_ways).node2_stacked = false;

            % No, endnode 1 is not stacked
            else
                
                % So endnode 2 must be stacked
                data(i_ways).node1_stacked = false;
                data(i_ways).node2_stacked = true;
            end
            
            % select next index to compare against way_ID
            i_stacked_nodes = i_stacked_nodes + 1;
          
        else
        % No, none of both endnodes are stacked
            data(i_ways).node1_stacked = false;
            data(i_ways).node2_stacked = false;
        end   
    end
    
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)


    % Visualize this stacked data
    if bool.plot_stacked_endnodes
        tic
        disp('Start visualizing all stacked endnodes (takes a few seconds) ...')
        
        % Extract all nodes
        x = [[data.x1]; [data.x2]];
        y = [[data.y1]; [data.y2]];
        
        % Extract node1 if it is stacked, else ignore it    
        x_node1_stacked = x(1, [data.node1_stacked]);
        y_node1_stacked = y(1, [data.node1_stacked]);
                    
        % Extract node2 if it is stacked, else ignore it
        x_node2_stacked = x(2, [data.node2_stacked]);
        y_node2_stacked = y(2, [data.node2_stacked]);       
      
        % Plot all nodes, highlight node1 and node2 if stacked
        figure
        hold on
        title('All ways with endnodes STACKED on XY-Map'), grid on
        xlabel('x - distance from midpoint [km]')
        ylabel('y - distance from midpoint [km]')
        
        plot(x, y, 'ok-')
        plot(x_node1_stacked, y_node1_stacked, 'xr');
        plot(x_node2_stacked, y_node2_stacked, '+b');
        
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
    end
    
    
    % plot histogram how many endnodes are stacked
    if bool.histogram_stacked_endnodes
        figure
        histogram(nodes_stacked_indices.unique_occurance + 1)
        title('Stacked endnodes: If stacked, how many are stacked?')
        xlabel('Nodes stacked on top of each other')
        ylabel('Number of different positions this occurs in')
    end
end

function [data, nodes_neighbouring_pairs] ...
	= my_calc_neighbouring_endnodes(data, distances, ...
                                    neighbourhood_threshold, bool)
                                
    % DESCRIPTION
    % This function searches every distance combination between all
    % endpoints which have a distance value bigger than "0" (the "0" case
    % was covered before) and lower then the treshold in
    % "neighbourhood_treshhold", which means that two endpoints
    % are in the vicinity, aka neighbourhood, to each other.
    % Since in the distance Matrix M every endnode needs two rows/columns, 
    % the original "ID" will be recalculate to get the right way element. 
    % To the dataset a boolean flag will be added to determine if endnode1/2
    % is in a neighbourhood. A list of all pairs of neighbouring endnodes will
    % be return for further grouping. Optionally data of all
    % neighbouring endnodes can be plotted and also a histogram of how many 
    % endnodes are in a neighbourhood can be shown.
    %
    % INPUT
    % data ... input dataset
    % distances ... distance Matrix M which contains distances between all
    %               endnodes
    % neighbourhood_threshold ... threshold-radius to determine if a
    %                             endnode is in a neighbourhood or not
    % bool ... boolean selector variable to toogle on/off the visualisations
    %
    % OUTPUT
    % data ... updated dataset, new flag: endnode1/2_neighbour
    % nodes_neighbouring_pairs ... list of all pairs of neighbouring endnodes
    
    tic
    disp('Start finding all neighbouring endnodes...')
    
    %%% Get IDs of all neighbouring endnodes
    % Create boolean logical index of all combinations which are in
    % neighourhood, but still not stacked
    b_dist_neighbourhood = distances < neighbourhood_threshold & distances > 0;
    
    % if no element is in neighbourhood region, cancel that function
    if not(any(any(b_dist_neighbourhood)))
        
        % Set all boolean flags to false
        [data(:).node1_neighbour] = deal(false);
        [data(:).node2_neighbour] = deal(false);
        
        % Create empty pseudo output
        nodes_neighbouring_pairs = [];

        % Print this information to console
        fprintf('   ... no endnode is in a neighbourhood! \n')
        
        % End that function
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
        return
    end    
    
    % Get the indices of this boolean matrix, hence the ids of elements
    [nodes_neighbour_indices.raw_column, nodes_neighbour_indices.raw_row] ...
        = find(b_dist_neighbourhood);
    
    % Combine the row(y)- and column(x)-indices in one list and sort them
    nodes_neighbour_indices.raw_combined ...
        = sort([nodes_neighbour_indices.raw_column; ...
                nodes_neighbour_indices.raw_row]);
        
    % remove duplicates: extract unique ids and calculate their occurances
    [nodes_neighbour_indices.unique_occurance, nodes_neighbour_indices.unique] ...
        = hist(nodes_neighbour_indices.raw_combined, ...
               unique(nodes_neighbour_indices.raw_combined));
           
    % match dimensions, hence transpose "unique_occurance"       
    nodes_neighbour_indices.unique_occurance ...
        = nodes_neighbour_indices.unique_occurance';
    
    fprintf('   ... %d endnodes are in same neighbourhood! \n', ...
        size(nodes_neighbour_indices.unique, 1))

    % Create new table, first column: unique occuring indices
    nodes_neighbouring = table(nodes_neighbour_indices.unique, ...
                          'VariableNames', {'index'});

    % Convert indices to Wayelement ID               
    nodes_neighbouring.way_ID = ceil(nodes_neighbouring.index / 2);   
   
    % Convert indices to boolean indicator if it's endnode1 (true) or 2 (false)
    nodes_neighbouring.endnode1 = mod(nodes_neighbouring.index, 2);
 
    % return all pairs, to group them later        
    nodes_neighbouring_pairs ...
        = [nodes_neighbour_indices.raw_row, nodes_neighbour_indices.raw_column];
    
    
    %%% Add neighbouring information to dataset
    % Start with first index
    i_neighbouring_nodes = 1;
    
    % Initialize frequent used variabel
    numel_way_IDs = numel(nodes_neighbouring.way_ID);
    
    % go through all ways in data_ways_selected
    for i_ways = 1 : size(data, 1)
        
        % Catch out-of-index-error if very last index (last way, endnode 2)
        % is a neighbour: Then break the loop
        if i_neighbouring_nodes > size(nodes_neighbouring, 1)
            
            % change variable so the next if check fails
            i_neighbouring_nodes = i_neighbouring_nodes - 1;
        end
        
        % Contains current way a neighbouring endnode? 
        if i_ways == nodes_neighbouring.way_ID(i_neighbouring_nodes)
        % Yes, at least one endnode is in neighbourhood
        
            % Are both endnodes neighbours?
            % Check if it isnt the last way_ID AND upcoming way_ID is identical
            if i_neighbouring_nodes < numel_way_IDs ...
                    && (nodes_neighbouring.way_ID(i_neighbouring_nodes) ...
                         == nodes_neighbouring.way_ID(i_neighbouring_nodes+1))
            
                % Yes, both endnodes are neighbours
                data(i_ways).node1_neighbour = true;
                data(i_ways).node2_neighbour = true;

                % Skip one index, since we just set two nodes
                i_neighbouring_nodes = i_neighbouring_nodes + 1; 
               
            % No, not both. So only one. Is endnode 1 a neighbour?  
            elseif nodes_neighbouring.endnode1(i_neighbouring_nodes)
                
                % Yes, endnode 1 is a neighbour
                data(i_ways).node1_neighbour = true;
                data(i_ways).node2_neighbour = false;

            % No, endnode 1 is not a neighbour
            else
                
                % So endnode 2 must be a neighbour
                data(i_ways).node1_neighbour = false;
                data(i_ways).node2_neighbour = true;
            end
            
            % select next index to compare against way_ID
            i_neighbouring_nodes = i_neighbouring_nodes + 1;
          
        else
        % No, none of both endnodes is a stacked one
            data(i_ways).node1_neighbour = false;
            data(i_ways).node2_neighbour = false;
        end      
    end
    
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)

    % Visualize this neighbouring data
    if bool.plot_neighbouring_endnodes
        tic
        disp(['Start visualizing all neighbouring endnodes ' ...
              '(takes a few seconds) ...'])
        
        % Extract all nodes
        x = [[data.x1]; [data.x2]];
        y = [[data.y1]; [data.y2]];
        
        % Extract node1 if it is in a neighbourhood, else ignore it    
        x_node1_neighbour = x(1, [data.node1_neighbour]);
        y_node1_neighbour = y(1, [data.node1_neighbour]);
                    
        % Extract node2 if it is in a neighbourhood, else ignore it
        x_node2_neighbour = x(2, [data.node2_neighbour]);
        y_node2_neighbour = y(2, [data.node2_neighbour]); 
        
        % Plot all nodes, highlight node1 and node2 if in neighourhood
        figure
        hold on
        title('All ways with endnodes NEIGHBOURING on XY-Map'), grid on
        xlabel('x - distance from midpoint [km]')
        ylabel('y - distance from midpoint [km]'),
       
        plot(x, y, 'ok-');
        plot(x_node1_neighbour, y_node1_neighbour, '*g');
        plot(x_node2_neighbour, y_node2_neighbour, '*g');
        
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
    end 
    
    % plot histogram how many endnodes are in the neighbourhood
    if bool.histogram_neighbouring_endnodes
        figure
        histogram(nodes_neighbour_indices.unique_occurance + 1, ...
                  max(nodes_neighbour_indices.unique_occurance))
        title('Neighbouring endnodes: How many will be in one group?')
        xlabel('Number of nodes which will be grouped together')
        ylabel('Number of different positions this occurs in')
    end
end

function list ...
	= my_group_nodes(pairs_input)

    % DESCRIPTION
    % This function takes as a input a list of pairs (stacked_pairs or
    % neighbouring_pairs) to group them: If A is a pair with B, C a pair
    % with D and B a pair with D, that means that there will be one group with
    % A, B, C and D. This function checks all cases, hence creates new
    % groups, adds elements to an existing group and even concentate groups:
    % If there is allready a group1 with A, B, C, D; and another 
    % group2 with X, Y, Z; and one pair C with Y comes up, then the new group
    % will be A, B, C, D, X, Y, Z. So group2 will be added to group1 and
    % group2 then deleted.
    %
    % INPUT
    % pairs_input ... list of pairs
    %
    % OUTPUT
    % list ... a list of groups made out of the pairs from pairs_input
    
    tic
    fprintf(['Start grouping all pairs from "%s" ' ...
             '(may take a few seconds)... \n'], inputname(1))
    
    % Initialize empty list
    list = [];
    
    % sort pairs horizontally
    pairs_sorted_horizontally = sort(pairs_input, 2);

    % sort pairs vertically in regards to 1st column
    data_paired = sortrows(pairs_sorted_horizontally);

    % Go through every pair, which consists of "partner1" and "partner2"
    for i_pairs = 1 : size(data_paired, 1)

        % Create "partner1" and "partner2 from current pair
        partner1 = data_paired(i_pairs, 1);
        partner2 = data_paired(i_pairs, 2);

        % If partner1 is already in any group, save its row, otherwise return 0
        [row_partner1, ~] = find(list == partner1, 1);
        
        % If partner2 is already in any group, save its row, otherwise return 0
        [row_partner2, ~] = find(list == partner2, 1);
        
        % So, is partner1 already in any group?
        if row_partner1
        % Yes, partner1 is in a group

            % So, Is partner2 in any group too?
            if row_partner2
            % Yes, both partner1 and 2 are in the same or in seperate groups

                % Are both in the same group?
                if row_partner2 == row_partner1
                % Yes, nothing to do

                    % Return to next iteration of for-loop
                    continue

                else           
                % No, special case:
                    % Two subgroups have formed, and need to be concatenated.
                    % So the whole group of partner 2 ("line2") will be copied
                    % to the end of the group of partner1 ("line1")

                    % Determine the values and number of values of line2
                    src_nonzero_values = nonzeros(list(row_partner2, :))';
                    src_num_nonzero_values = numel(src_nonzero_values);

                    % Calculate the exact position in line1 to where the 
                    % nonzero values of line2 will be copied too
                    dest_num_nonzero_values = nnz(list(row_partner1, :));
                    dest_start_pos = dest_num_nonzero_values + 1;
                    dest_end_pos ...
                        = dest_num_nonzero_values + src_num_nonzero_values;

                    % Copy the values of line2 to the end of line1
                    list(row_partner1, dest_start_pos : dest_end_pos) ...
                        = src_nonzero_values;

                    % Sort line1
                    sorted_values = sort(nonzeros(list(row_partner1, :))', 2);
                    trailing_zeros = zeros(sum(list(row_partner1, :) == 0), 1)';
                    list(row_partner1, :) = [sorted_values, trailing_zeros];

                    % Delete line2
                    list(row_partner2, :) = [];
                end

            else
            % No, partner2 is in no group yet

                % Add partner2 at the end of partner1's row
                num_values = nnz(list(row_partner1, :));
                list(row_partner1, num_values + 1) = partner2;

                % Sort partner1's row
                sorted_values = sort(nonzeros(list(row_partner1,:))', 2);
                trailing_zeros = zeros(sum(list(row_partner1,:) == 0), 1)';
                list(row_partner1,:) = [sorted_values, trailing_zeros];
            end

        % No, partner1 is in no group. Is partner2 in any group?
        elseif row_partner2
        % Yes, at least partner2 is in a group

            % Add partner1 at the end of partner2's row
            num_values = nnz(list(row_partner2, :));
            list(row_partner2, num_values + 1) = partner1;

            % Sort partner2's row
            sorted_values = sort(nonzeros(list(row_partner2, :))', 2);
            trailing_zeros = zeros(sum(list(row_partner2, :) == 0), 1)';
            list(row_partner2,:) = [sorted_values, trailing_zeros];

        else
        % No, neither partner1 nor partner2 are in any group 

           % Add new group with both partner1 and partner2
           trailing_zeros = zeros(1, size(list, 2) - 2);
           newrow = [[partner1, partner2], trailing_zeros];
           list = [list; newrow];       
        end
    end

    fprintf(['   ... %d nodes will be grouped together in %d grouped nodes,'...
             '\n       with an average of %4.2f nodes ' ...
             'per grouped node. \n'], ...
             sum(sum(list ~= 0, 2)), numel(sum(list ~= 0, 2)), ...
             sum(sum(list ~= 0, 2)) / numel(sum(list ~= 0, 2)))
         
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end
                 
function data ...
	= my_group_stacked_endnodes(data, nodes_stacked_grouped)
    
    % DESCRIPTION
    % This funciton gets the ID and lon/lat/x/y coordinates of the first
    % member of a stacked group and copies it to all the other members of
    % that group, therefore giving all members the same node ID and
    % (exactly) same coordinate.
    %
    % INPUT
    % data ... original dataset
    % nodes_stacked_grouped ... list of nodes which are stacked
    %
    % OUTPUT
    % data ... updated dataset where all stacked nodes have the same group
    %          node id
   
    tic
    disp('Start adding coordinates of stacked groups... ')

    % Preallocate new fields, so that they are in the right order
    [data(:).ID_node1_grouped] = deal(NaN);
    [data(:).ID_node2_grouped] = deal(NaN);
    [data(:).lon1_grouped] = deal(NaN);
    [data(:).lat1_grouped] = deal(NaN);
    [data(:).lon2_grouped] = deal(NaN);
    [data(:).lat2_grouped] = deal(NaN);
    [data(:).x1_grouped] = deal(NaN);
    [data(:).y1_grouped] = deal(NaN);
    [data(:).x2_grouped] = deal(NaN);
    [data(:).y2_grouped] = deal(NaN);
    
    % extract first group coordinates of all stacked groups
    for i_group = 1 : size(nodes_stacked_grouped, 1)

        % Save the node_ID of first group member
        i_node_ID = nodes_stacked_grouped(i_group, 1);

        % Convert the node_ID in the way_ID
        i_way_ID = ceil(i_node_ID / 2);

        % Extract from the node_ID the boolean information, if  
        % it is node1 (true) or node2 (false)
        b_node1 = mod(i_node_ID, 2);

        if b_node1
             % get ID/coordinates of node 1
             grouped_node_ID = data(i_way_ID).ID_node1;
             grouped_lat = data(i_way_ID).lat1;
             grouped_lon = data(i_way_ID).lon1;        
             grouped_x = data(i_way_ID).x1;
             grouped_y = data(i_way_ID).y1; 
        else
            % get ID/coordinates of node 2
            grouped_node_ID = data(i_way_ID).ID_node2;
            grouped_lat = data(i_way_ID).lat2;
            grouped_lon = data(i_way_ID).lon2;
            grouped_x = data(i_way_ID).x2;
            grouped_y = data(i_way_ID).y2; 
        end
        
        % go through every (nonzero) member of that group       
        for i_group_member = 1 : nnz(nodes_stacked_grouped(i_group, :))

            % Save the node_ID of that group member
            i_node_ID = nodes_stacked_grouped(i_group, i_group_member);

            % Convert the node_ID in the way_ID
            i_way_ID = ceil(i_node_ID / 2);

            % Extract from the node_ID the boolean information, if  
            % it is node1 (true) or node2 (false)
            b_node1 = mod(i_node_ID, 2);

            if b_node1
                % add the new combined id/lat/lon
                data(i_way_ID).ID_node1_grouped = grouped_node_ID;
                data(i_way_ID).lat1_grouped = grouped_lat;
                data(i_way_ID).lon1_grouped = grouped_lon;
                data(i_way_ID).x1_grouped = grouped_x;
                data(i_way_ID).y1_grouped = grouped_y;                
            else
                % add the new combined id/lat/lon
                data(i_way_ID).ID_node2_grouped = grouped_node_ID;
                data(i_way_ID).lat2_grouped = grouped_lat;
                data(i_way_ID).lon2_grouped = grouped_lon;
                data(i_way_ID).x2_grouped = grouped_x;
                data(i_way_ID).y2_grouped = grouped_y;                   
            end     
        end      
    end
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)
end

function [data, grouped_xy_coordinates] ...
    = my_group_neighbouring_endnodes(data, nodes_neighbouring_grouped, ...
                                     degrees_to_km_conversion)

    % DESCRIPTION
    % This function extracts all lon/lat coordinates of all members for every
    % neighbouring group, then calculates the mean lon/lat value and copies
    % it to every group member. Then the x/y values will newly be
    % calculated and too added.
    %
    % INPUT
    % data ... origial input dataset
    % nodes_neighbouring_grouped ... list with nodes grouped
    % degrees_to_km_conversion ... conversion data to calculate x/y coordinates
    %
    % OUTPUT
    % data ... updated dataset with grouped fields
    % grouped_xy_coordinates ... list of x/y coordinates of grouped nodes,
    %                            this will be used in a plot later
      
    tic
    disp('Start adding grouping neighbours... ')                      
                                 
    % Precalculation for improved code readabilty                                
    num_of_groups = size(nodes_neighbouring_grouped, 1);
    
    % Preallocate output (otherwise error if no ways will be grouped)
    grouped_xy_coordinates = [];

    % extract all coordinates of all neighbouring group members
    for i_group = 1 : num_of_groups

        % go through every (nonzero) member of that group
        for i_group_member = 1 : nnz(nodes_neighbouring_grouped(i_group, :))
        
            % Save the node_ID of that group member
            i_node_ID = nodes_neighbouring_grouped(i_group, i_group_member);

            % Convert the node_ID in the way_ID
            i_way_ID = ceil(i_node_ID / 2);

            % Extract from the node_ID the boolean information, if  
            % it is node1 (true) or node2 (false)
            b_node1 = mod(i_node_ID, 2);

            if b_node1
                % get coordinates of node 1
                lon = data(i_way_ID).lon1; 
                lat = data(i_way_ID).lat1;       
                x = data(i_way_ID).x1;
                y = data(i_way_ID).y1; 
            else
                % get coordinates of node 2
                lon = data(i_way_ID).lon2;
                lat = data(i_way_ID).lat2;      
                x = data(i_way_ID).x2;
                y = data(i_way_ID).y2; 
            end

            % Save the coordinates of that group member in alternating manner
            % lon of member1 in column 1, lat of member1 in column 2,
            % lon of member2 in column 3, lat of member2 in column 4, etc.
            grouped_lonlat_coordinates(i_group, i_group_member * 2 - 1) = lon;
            grouped_lonlat_coordinates(i_group, i_group_member * 2) = lat;  

            % Do the same with x/y
            % x of member1 in column 1, y of member1 in column 2,
            % x of member2 in column 3, y of member2 in column 4, etc.
            grouped_xy_coordinates(i_group, i_group_member * 2 - 1) = x;
            grouped_xy_coordinates(i_group, i_group_member * 2) = y;      
        end 
    end

    % Preallocate the list of mean coordinates
    list_coordinates_mean = zeros(size(nodes_neighbouring_grouped, 1), 2);

    % calculate mean lon/lat for every group
    for i_group = 1 : num_of_groups

        % save all lon/lat
        lon_data = grouped_lonlat_coordinates(i_group, 1:2:end);
        lat_data = grouped_lonlat_coordinates(i_group, 2:2:end);    
        
        % remove all zeros, since they would miscalculate the mean value
        lon_data = lon_data(lon_data ~= 0);    
        lat_data = lat_data(lat_data ~= 0);

        % calculate the mean value and save it
        list_coordinates_mean(i_group, 1:2) = [mean(lon_data), mean(lat_data)];
    end
    
    % Add the grouped coordinates of every group to dataset
    for i_group = 1 : num_of_groups

        % go through every (nonzero) member of that group
        for i_group_member = 1 : nnz(nodes_neighbouring_grouped(i_group, :))

            % Save the node_ID of that group member
            i_node_ID = nodes_neighbouring_grouped(i_group, i_group_member);

            % Convert the node_ID in the way_ID
            i_way_ID = ceil(i_node_ID / 2);

            % Extract from the node_ID the boolean information, if  
            % it is node1 (true) or node2 (false)
            b_node1 = mod(i_node_ID, 2);

            if b_node1
                % add the new combined id/lat/lon
                data(i_way_ID).ID_node1_grouped = i_group;
                data(i_way_ID).lon1_grouped = list_coordinates_mean(i_group, 1);                
                data(i_way_ID).lat1_grouped = list_coordinates_mean(i_group, 2);
            else
                % add the new combined id/lat/lon
                data(i_way_ID).ID_node2_grouped = i_group;
                data(i_way_ID).lon2_grouped = list_coordinates_mean(i_group, 1);
                data(i_way_ID).lat2_grouped = list_coordinates_mean(i_group, 2);
            end     
        end
    end
    
    
    %%% Add x/y coordinates to the new groups
    % Extract input data into varables
    km_per_lon_deg = degrees_to_km_conversion(1); 
    km_per_lat_deg = degrees_to_km_conversion(2);                  
    mean_lon = degrees_to_km_conversion(3);                  
    mean_lat = degrees_to_km_conversion(4);
   
    % calculate the difference in degree for each point from mean  
    delta_lon1 = [data.lon1_grouped]' - mean_lon;
    delta_lon2 = [data.lon2_grouped]' - mean_lon;      
    delta_lat1 = [data.lat1_grouped]' - mean_lat;
    delta_lat2 = [data.lat2_grouped]' - mean_lat; 
   
    % convert the delta_degree into delta_kilometer
    x1 = num2cell(delta_lon1 * km_per_lon_deg);
    x2 = num2cell(delta_lon2 * km_per_lon_deg);
    y1 = num2cell(delta_lat1 * km_per_lat_deg);
    y2 = num2cell(delta_lat2 * km_per_lat_deg);    
    
    % save delta_km to data_ways (raw data or new combined coordinates)
    [data.x1_grouped] = x1{:};
    [data.y1_grouped] = y1{:};
    [data.x2_grouped] = x2{:};
    [data.y2_grouped] = y2{:};             
    
    
    % If id_node1/2_grouped does not exist, this script will calculate
    % x1/2_new and y1/2_new with wrong (=0) lat1/2_grouped and lat1/2_grouped.
    % Correct for it by deleting those values
    for i_ways = 1 : numel(data)
    
        % set node1_new id/x/y empty
        if isnan(data(i_ways).ID_node1_grouped)
            data(i_ways).ID_node1_grouped = [];
            data(i_ways).x1_grouped = [];
            data(i_ways).y1_grouped = [];
            data(i_ways).lon1_grouped = [];                
            data(i_ways).lat1_grouped = [];
        end

        % set node1_new id/x/y empty
        if isnan(data(i_ways).ID_node2_grouped)
            data(i_ways).ID_node2_grouped = [];
            data(i_ways).x2_grouped = [];
            data(i_ways).y2_grouped = [];           
            data(i_ways).lon2_grouped = [];   
            data(i_ways).lat2_grouped = [];           
        end  
    end  
    
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)   
end  

function data ...
    = my_add_final_coordinates(data)
    
    % DESCRIPTION
    % This function selects the final coordinates: If one or both endnodes
    % got grouped (because they were stacked and/or in a neighourhood),
    % those new grouped coordinates will be the final coordinates. If not,
    % then the original coordinates will be taken as the final coordinates.
    % The final coordinate will constists the ID, the lon/lat and the x/y
    % coordinates.
    %
    % INPUT
    % data ... original dataset
    %
    % OUTPUT
    % data .. updated dataset with new final coordinates fields
       
    tic
    disp('Start adding final coordinates...')
    
    % First, go through all ways and get the new endnode coordinates
    for i_ways = 1 : numel(data)

        % Check if there is a new node 1, if not, take old one
        if isempty(data(i_ways).ID_node1_grouped)
            data(i_ways).ID_node1_final = data(i_ways).ID_node1;
            data(i_ways).lon1_final = data(i_ways).lon1;
            data(i_ways).lat1_final = data(i_ways).lat1;
            data(i_ways).x1_final = data(i_ways).x1;
            data(i_ways).y1_final = data(i_ways).y1;            
        else
            data(i_ways).ID_node1_final = data(i_ways).ID_node1_grouped;
            data(i_ways).lon1_final = data(i_ways).lon1_grouped;
            data(i_ways).lat1_final = data(i_ways).lat1_grouped;
            data(i_ways).x1_final = data(i_ways).x1_grouped;
            data(i_ways).y1_final = data(i_ways).y1_grouped;
        end

        % Check if there is a new node 2, if not, take old one
        if isempty(data(i_ways).ID_node2_grouped)
            data(i_ways).ID_node2_final = data(i_ways).ID_node2;
            data(i_ways).lon2_final = data(i_ways).lon2;
            data(i_ways).lat2_final = data(i_ways).lat2;
            data(i_ways).x2_final = data(i_ways).x2;
            data(i_ways).y2_final = data(i_ways).y2;
        else
            data(i_ways).ID_node2_final = data(i_ways).ID_node2_grouped;         
            data(i_ways).lon2_final = data(i_ways).lon2_grouped;
            data(i_ways).lat2_final = data(i_ways).lat2_grouped;
            data(i_ways).x2_final = data(i_ways).x2_grouped;
            data(i_ways).y2_final = data(i_ways).y2_grouped;
        end  
    end
    
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end


%==========================================================================
%% Export
function [data, data_singular_ways] ...
    = my_delete_singular_ways(data)

    % DESCRIPTION
    % This function deletes all ways which have the same endpoints after
    % grouping, hence got "shrinked" into a singularity. This happens when
    % short lines, for example in a substation, are in the
    % grouping/neighbouring radius of multiply points. Then the endpoints
    % will be concentated in a single endpoint, hence the line
    % "disappears". Since those lines are for no further use, they will be
    % deleted prior exporting.
    %
    % INPUT
    % data ... orginal dataset
    %
    % OUTPUT
    % data ... new dataset with singularity-ways deleted
    
    tic
    disp('Start deleting ways which have the same endpoints after grouping...')
                      
    % Initialize list of singular Way-Element IDs
    way_IDs_singular = [];
    
    % Go through all ways
    for i_ways = 1 : numel(data)

        % if both IDs are identical, mark them in a "to-delete" list
        if data(i_ways).ID_node1_final == data(i_ways).ID_node2_final
            way_IDs_singular = [way_IDs_singular, i_ways];
        end     
    end
    
    % Save all singular ways in sepearte variable prior deleting
    data_singular_ways = data(way_IDs_singular);
    
    % Delete all ways which have identical endpoints from original dataset
    data(way_IDs_singular) = [];
    
    fprintf('   ... %d ways were deleted! \n', numel(way_IDs_singular))
    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc)
end     

function [data_ways_selected, lengths] ...
    = my_calc_real_lengths(data_ways_selected, data_ways_all, ...
                           data_nodes_all, bool)
                       
    % DESCRIPTION
    % This function calculates the real length of a line. It fetches all
    % coordinates off all nodes of all UIDs, calculates the lenght between
    % those segments and adds them all up to calcule the real length.
    %
    % INPUT
    % data_ways_selected ... from which ways the real length should be
    %                        calcuated
    % data_ways_all ... no ways have been doubled here, so fetch data here
    % data_nodes_all ... get all coordinates of all nodes
    % bool ... toogle on / off the whole function and specify visualisation
    %
    % OUTPUT
    % data_ways_selected ... give each way its real line length
    % lengths ... the struct used to calcualte the real line lengths
    
    disp('Start calculating real length of lines...')
    
    if bool.calculate_real_line_length
        tic

        %%% Create variable with all coordinates of all nodes of all UID ways

        % Get all the ways UIDs which real lengths we want to calculate
        unique_UIDs = unique([data_ways_selected.UID]);

        % Create a list of all node ids
        list_all_node_IDs = [data_nodes_all(:).id]';

        % Initalize the reverse string for realtime percentage status update
        reverse_string = [];

        % Calculate the number of UID-Ways
        numel_uids = numel(unique_UIDs);

        % go through every UID
        for i_uid = 1 : numel_uids

            % Get the position of current UID in data_ways_all
            i_ways = find([data_ways_all.UID] == unique_UIDs(i_uid), 1);
            
            % Copy relevant information (UID, way_ID) of that UID
            lengths(i_uid).UID = data_ways_all(i_ways).UID;
            lengths(i_uid).way_id = data_ways_all(i_ways).id;

            % Go through every node of that UID
            for i_node = 1 : numel(data_ways_all(i_ways).nodes)

                % get current node ID
                current_node_id = data_ways_all(i_ways).nodes(i_node);

                % add current node id as field to that node
                lengths(i_uid).nodes(i_node).id = current_node_id;

                % Find the position of current node id in list_all_node_IDs
                position_current_node ...
                    = find(current_node_id == list_all_node_IDs, 1);

                % use this position to copy lon/lat coordinates of current node                 
                lon = data_nodes_all(position_current_node).lon;
                lat = data_nodes_all(position_current_node).lat;  

                % Add coordinates of current node ID to that node
                lengths(i_uid).nodes(i_node).lon = lon;
                lengths(i_uid).nodes(i_node).lat = lat;

                % Assign field "next coordinate"
                % If list A, B C, D; then next coordinate for A is B and [] for D
                if i_node == 1         

                    % the first node cant be a "next node", so skip it
                    continue;         

                else    

                    % assign current coordinate to previous node as "next node"
                    lengths(i_uid).nodes(i_node - 1).next_lon = lon;
                    lengths(i_uid).nodes(i_node - 1).next_lat = lat;          
                end          
            end    

            % Copy length as last field
            lengths(i_uid).length_org = data_ways_all(i_ways).length;

            %%% Print progress to console

            % Calculate current percentage
            percent_done = 100 * i_uid / numel_uids;

            % Create new string
            string = sprintf(['   ... fetching coordinates of all nodes of way ' ...
                              '%d of %d (%4.2f Percent)... \n'], ...
                              i_uid, numel_uids, percent_done);

            % Delete old string, print new string           
            fprintf([reverse_string, string]);

            % Create the next "delete old string"-string. \b = backlash/return key
            reverse_string = repmat(sprintf('\b'), 1, length(string));      
        end

        %%% Calculate beeline distance of each way   
        disp('   ... calculating length of each line segment...')

        % Set the earth radius in km
        earth_radius = 6371;

        % Go through all UIDs
        for i_uid = 1 : numel_uids

            % Get start coordinate of each line segment in rad
            lon_start_rad = lengths(i_uid).nodes(1).lon * pi / 180;
            lat_start_rad = lengths(i_uid).nodes(1).lat * pi / 180;

            % Get end coordinate of each line segment in rad
            lon_end_rad = lengths(i_uid).nodes(end).lon * pi / 180;
            lat_end_rad = lengths(i_uid).nodes(end).lat * pi / 180;

            % calculate difference between coordinates
            delta_lon_rad = (lon_end_rad - lon_start_rad);
            delta_lat_rad = lat_end_rad - lat_start_rad;

            % use Equierectangular approximation formular to calculate lenghts
            % Credits/Source: https://www.movable-type.co.uk/scripts/latlong.html
            x = delta_lon_rad .* cos((lat_start_rad + lat_end_rad) ./ 2);
            y = delta_lat_rad;
            length_of_line = sqrt(x.^2 + y.^2) * earth_radius;

            % Add that length to each way element
            lengths(i_uid).length_beeline = length_of_line;
        end

        %%% Calculate distances of each segment
        % Go through all UIDs
        for i_uid = 1 : numel_uids

            % Get all starting coordinates of each line segment
            lons_start = [lengths(i_uid).nodes.lon];
            lats_start = [lengths(i_uid).nodes.lat];

            % Last node can't be a start coordinate
            lons_start(end) = [];
            lats_start(end) = [];

            % Get all ending coordinates of each line segment
            lons_end = [lengths(i_uid).nodes.next_lon];
            lats_end = [lengths(i_uid).nodes.next_lat];

            % Convert degrees to radians
            lons_start_rad = lons_start * pi / 180;
            lats_start_rad = lats_start * pi / 180;
            lons_end_rad = lons_end * pi / 180;
            lats_end_rad = lats_end * pi / 180;

            % calculate difference between coordinates
            delta_lons_rad = (lons_end_rad - lons_start_rad);
            delta_lats_rad = lats_end_rad - lats_start_rad;

            % use Equierectangular approximation formular to calculate lenghts
            % Credits/Source: https://www.movable-type.co.uk/scripts/latlong.html
            x = delta_lons_rad .* cos((lats_start_rad + lats_end_rad) ./ 2);
            y = delta_lats_rad;
            lengths_of_segments = sqrt(x.^2 + y.^2) * earth_radius;

            % Go through all but last segments of current way
            for i_nodes = 1 : numel(lengths(i_uid).nodes) - 1

                % Add length of each segment to each segment
                lengths(i_uid).nodes(i_nodes).segment_lengths ...
                    = lengths_of_segments(i_nodes);
            end

            % Add length of whole line (sum of segments) to current way element
            lengths(i_uid).length_all_segments = sum(lengths_of_segments);
            
            % Add length-difference in percent
            lengths(i_uid).length_diff_in_percent ...
                = lengths(i_uid).length_all_segments ...
                  ./ lengths(i_uid).length_beeline * 100 - 100;

            % Add absolut length-difference in kilometer
            lengths(i_uid).length_diff_absolut_in_km ...
                = lengths(i_uid).length_all_segments ...
                   - lengths(i_uid).length_beeline;

            % Add length-difference between org/beeline in percent
            lengths(i_uid).length_diff_between_org_and_beeline_percent ...
                = lengths(i_uid).length_org ./ lengths(i_uid).length_beeline ...
                  * 100 - 100;
        end
        
        %%% Add that length to data_ways_selected too
        % Initialize that new field
        data_ways_selected(1).length_real = [];
        
        for i_uid = 1 : numel_uids
            
            % get current UID and its real length
            current_UID = lengths(i_uid).UID;
            current_real_length = lengths(i_uid).length_all_segments;
            
            % Create boolean index which elements have current UID
            b_current_UID = [data_ways_selected.UID] == current_UID;
            
            % Add to all these elements a new field with real length
            [data_ways_selected(b_current_UID).length_real] ... 
                = deal(current_real_length);          
        end

        % Transpose lengths to match the other dimension
        lengths = lengths';
        
        if bool.plot_comparison_real_beeline
        tic
        disp('Start ploting comparison between real line course and beeline')
            % Visualisation of that lengths
            figure
            hold on
            grid on
            title('Comparison between real line course and beeline')
            xlabel('Longitude [°]'), ylabel('Latitude [°]')

            % Go throuh every UID
            for i_uid = 1 : numel_uids

                % Plot that way only if two criterias are made
                if lengths(i_uid).length_diff_in_percent ...
                      > bool.beeline_visu_treshold_diff_percent ...
                   && lengths(i_uid).length_diff_absolut_in_km ...
                      > bool.beeline_visu_treshold_diff_absolut

                    % Plot line between endpoints in lines with "x" as endpoint
                    bee_line_lon = [lengths(i_uid).nodes(1).lon; ...
                                    lengths(i_uid).nodes(end).lon];
                    bee_line_lat = [lengths(i_uid).nodes(1).lat; ...
                                    lengths(i_uid).nodes(end).lat];
                    plot(bee_line_lon, bee_line_lat, 'x-k', 'LineWidth', 1, ...
                        'Markersize', 8)

                    % Plot real line course as colorful ".-" segments on top
                    lons_segments = [lengths(i_uid).nodes.lon];
                    lats_segments = [lengths(i_uid).nodes.lat];
                    plot(lons_segments, lats_segments, '.-')
                end
            end
        end
    else
        fprintf(['   ATTENTION: Real line lenght WONT be calculted! \n' ...
                 '              Beeline-length (Luftlinie) will be used. \n'])
        lengths = "Real line lengths have NOT been calculated!";
    end
    
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end

function data_tags ...
    = my_get_tags(data)

    % DESCRIPTION
    % Since the database of Openstreetmap varies greatly, not all ways have
    % the same set of "tags". In this matlab script only a few, very
    % common, tags can be consider in an automatic approach. There may be
    % still useful information in the tags, so all tags will be copied to a
    % seperate variable, which then will be exported as "sheet2" in the
    % final exported excel file. There all tags can manualley be reviewd
    % for further investigation.
    %
    % INPUT
    % data ... dataset prior to exporting
    %
    % OUTPUT
    % data_tags ... all tags off all way elements
    
    tic
    disp('Start extracting all tags from all ways...')
    
    % Preallocate new struct and start number of tag fields counter
    data_tags.UID = [];
    i_ways_tags = 1;
    
    % go through every way
    for i_ways = 1 : numel(data)
        
        % if current way/UID was cloned somewhere in this skript, skip it
        if i_ways > 1 && data_tags(i_ways_tags - 1).UID == data(i_ways).UID
            continue;        
        end
    
        % Save UID
        data_tags(i_ways_tags).UID = data(i_ways).UID;
        
        % get all tag-fieldnames of current way
        fieldnames_current_way = fieldnames(data(i_ways).tags);
        
        % Add the values of all tags to data_tag
        for i_fieldname = 1 : numel(fieldnames_current_way)
            
            % Get current field name
            current_fieldname = fieldnames_current_way{i_fieldname};
            
            % Get value of current field name
            value = data(i_ways).tags.(current_fieldname);
            
            % copy that value in the correspondending field
            data_tags(i_ways_tags).(current_fieldname) = value;       
        end
        
        % increase tags counter (i. E., got to next UID which is in list)
        i_ways_tags = i_ways_tags + 1;
    end   
    
    % Transpose Output to match workspace dimensions
    data_tags = data_tags';

    fprintf('   ... finished! (%5.3f seconds) \n \n' , toc) 
end

function data_new ...
    = my_add_LtgsID_clone_ways(data, export_excel_country_code)

    % DESCRIPTION
    % This function creates the "LtgsID", "Leitungs-ID"/"way ID" for every
    % way elment. The LtgsID is the main "name" a way has. The
    % LtgsID consist of the two character countrycode defined earlier and a
    % 4 digit counter. Ways, which need to be cloned (since they carry
    % more than one system) will be duplicated/tripled or quadrupled and
    % get an updated LtgsID with an "a, b, c" suffix.
    %
    % INPUT
    % data ... input dataset
    % export_excel_country_code ... the two-digit country code 
    %
    % OUTPUT
    % data_new ... new dataset with cloned ways and field "LtgsID" 
    
    tic
    disp('Start adding "LtgsID" and cloning ways...')
    
    % Initialize variables
    num_of_ways = numel(data);
    num_of_doubled_ways = 0;
    num_of_tripled_ways = 0;
    num_of_quadrupled_ways = 0;
    i_ways_new = 1;
   
    % Create 'LtgsID'
    LtgsID_Prefix = strcat('LTG', export_excel_country_code);
    LtgsID = strcat(repmat(LtgsID_Prefix, num_of_ways, 1), ...
                    num2str([1 : num_of_ways]', '%04.f'));
                
    % Add 'LtgsID' to data
    for i_ways = 1 : num_of_ways
        data(i_ways).LtgsID = LtgsID(i_ways);        
    end
   
    % Clone ways
    for i_ways = 1 : num_of_ways + num_of_doubled_ways ...
                                 + num_of_tripled_ways ...
                                 + num_of_quadrupled_ways
        
        % Run only if a way needs to be doubled
        if data(i_ways).systems == 2         
            
            % Get a copy of that way
            cloned_way_b = data(i_ways);
            
            % Get LtgsID 
            LtgsID_current = data(i_ways).LtgsID;            
            
            % Update LtgsID on the original way and its clone
            data(i_ways).LtgsID = strcat(LtgsID_current, 'a');         
            cloned_way_b.LtgsID = strcat(LtgsID_current, 'b');
              
            % Insert the cloned data way
            data_new(i_ways_new : i_ways_new+1) = [data(i_ways); cloned_way_b];

            % Increase counter of ways
            num_of_doubled_ways = num_of_doubled_ways + 1;
            
            % Skip next way since it is the duplicated one
            i_ways_new = i_ways_new + 2;
            
            
        % Run only if a way needs to be tripled
        elseif data(i_ways).systems == 3
 
            % Get two copies of that way
            [cloned_way_b, cloned_way_c] = deal(data(i_ways));
            
            % Get LtgsID 
            LtgsID_current = data(i_ways).LtgsID;            
            
            % Update LtgsID on the original way and its clone
            data(i_ways).LtgsID = strcat(LtgsID_current, 'a');         
            cloned_way_b.LtgsID = strcat(LtgsID_current, 'b');          
            cloned_way_c.LtgsID = strcat(LtgsID_current, 'c');  
            
            % Insert the cloned data way
            data_new(i_ways_new : i_ways_new + 2) ...
                = [data(i_ways); cloned_way_b; cloned_way_c];

            % Increase counter of ways
            num_of_tripled_ways = num_of_tripled_ways + 2;   
            
            % Skip next two ways since they are the duplicated
            i_ways_new = i_ways_new + 3;

            
        % Run only if a way needs to be quadrupled
        elseif data(i_ways).systems == 4
 
            % Get twi copies of that way
            [cloned_way_b, cloned_way_c, cloned_way_d] = deal(data(i_ways));
            
            % Get LtgsID 
            LtgsID_current = data(i_ways).LtgsID;            
            
            % Update LtgsID on the original way and its clone
            data(i_ways).LtgsID = strcat(LtgsID_current, 'a');         
            cloned_way_b.LtgsID = strcat(LtgsID_current, 'b');          
            cloned_way_c.LtgsID = strcat(LtgsID_current, 'c');  
            cloned_way_d.LtgsID = strcat(LtgsID_current, 'd'); 
            
            % Insert the cloned data way
            data_new(i_ways_new : i_ways_new + 3) ...
                = [data(i_ways); cloned_way_b; cloned_way_c; cloned_way_d];

            % Increase counter of ways
            num_of_quadrupled_ways = num_of_quadrupled_ways + 3;   
            
            % Skip next two ways since they are the duplicated
            i_ways_new = i_ways_new + 4;
            
            
        % No way needs to be cloned
        else
            % copy current way to new struct
            data_new(i_ways_new) = data(i_ways);
            
            % Increase next-way counter
            i_ways_new = i_ways_new + 1;
        end        
    end
    
    % Transpose the new data set to match others in workspace
    data_new = data_new';
    
    
    fprintf('   ... %d ways have been doubled, %d tripled, %d quadrupled.\n',...
            num_of_doubled_ways, num_of_tripled_ways / 2, ...
            num_of_quadrupled_ways / 3)
        
    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end

function data ...
    = my_export_excel(data, export_excel_country_code, data_tags, ...
                      way_length_multiplier)

    % DESCRIPTION
    % This function exports the data to two excel files. Every unique endnode
    % will recive a NUID (unique node ID), this too will be added to the
    % added to the dataset. Columns will be created so that ALTANTIS can
    % read the excel file. In the annotation ("Bemerkung") column additinal
    % information will be written if necessary.
    %
    % INPUT
    % data ... the dataset to export
    % export_excel_country_code ... the countrycode to name LtgsID and NUID
    % data_tags ... all values off all fields of all tags of all way elements
    %
    % OUTPUT
    % data ... updated dataset (NUID have been added)
    % (two Excel files in current directory: tbl_Stamm_Leitungen & _Knoten)  
    
    tic
    disp('Start exporting data to Excel files... (may take a few seconds)')
       
    % Initalize and preallocate variables used in this script
    num_of_ways = numel(data);
 

    %%% Assign NUID (=Node Unique ID)
    % Preallocating variables used in for loop
    [node1_data, node2_data] = deal(zeros(num_of_ways, 1));
    
    % Get relevant data of nodes               
    node1_data(:, 1) = [data(:).ID_node1_final];
    node1_data(:, 2) = [data(:).voltage];
    node1_data(:, 3) = [data(:).lon1_final];
    node1_data(:, 4) = [data(:).lat1_final];
    
    node2_data(:, 1) = [data(:).ID_node2_final];
    node2_data(:, 2) = [data(:).voltage];
    node2_data(:, 3) = [data(:).lon2_final];
    node2_data(:, 4) = [data(:).lat2_final];
    
    % Get every unique node / voltage level combination
    nodes_unique = unique([node1_data; node2_data], 'rows', 'first');
    
    % Create unique IDs for the nodes, "NUID" = Node_Unique_ID
    num_of_unique_nodes = size(nodes_unique, 1);  
    country_code = repmat(export_excel_country_code, num_of_unique_nodes, 1);
    counter = string(num2str([1 : num_of_unique_nodes]', '%05.f'));
    nuid = strcat(country_code, counter);
                          
    % Combine the ID and the list of unique nodes into a conversion file               
    nodes_conversion = [cellstr(nuid), num2cell(nodes_unique)];
    
    % Go throuh every NUID and assign it to data_ways_selected
    % where the node ID and the voltage level matches
    for i_nuid = 1 : size(nodes_unique, 1)
        
        % Get the orignal node ID of current NUID
        node_org_ID = cell2mat(nodes_conversion(i_nuid, 2));
        
        % Get the voltage level of current NUID
        node_org_voltage = cell2mat(nodes_conversion(i_nuid, 3));
        
        % Create a boolean index which node1 has exactly that org_ID
        b_node1_ID_match = node1_data(:, 1) == node_org_ID;
        b_node2_ID_match = node2_data(:, 1) == node_org_ID;
        
        % Create a boolean index which voltage matches current NUID voltage
        b_node1_voltage_match = node1_data(:, 2) == node_org_voltage;
        b_node2_voltage_match = node2_data(:, 2) == node_org_voltage;
        
        % Create a boolean index when both conditions are met
        b_node1_id_and_voltage_ok = b_node1_ID_match & b_node1_voltage_match;
        b_node2_id_and_voltage_ok = b_node2_ID_match & b_node2_voltage_match;
        
        % assign every node which satifies both conditions current NUID
        [data(b_node1_id_and_voltage_ok).node1_nuid] = deal(nuid(i_nuid));
        [data(b_node2_id_and_voltage_ok).node2_nuid] = deal(nuid(i_nuid));
    end
      
    
    %%% Create strings for the Annotation "Bemerkung" column   
    % Prealloacte Annotations string
    str_annotation = cell(num_of_ways, 1);
    
    % go through all ways
    for i_ways = 1 : num_of_ways
                  
        % Create string if current way has multiple voltage levels
        if data(i_ways).vlevels ~= 1
            str_annotation{i_ways, 1} = strcat(str_annotation{i_ways, 1}, ...
                                               ", multiple vlevels");   
        end
     
        % Create string if current way is doubled/tripled/quadrupelt
        if data(i_ways).systems == 2
            str_annotation{i_ways, 1} = strcat(str_annotation{i_ways, 1}, ...
                                               ", 6 cables - 2 systems");     
            
        elseif data(i_ways).systems == 3
            str_annotation{i_ways, 1} = strcat(str_annotation{i_ways, 1}, ...
                                               ", 9 cables - 3 systems"); 
            
        elseif data(i_ways).systems == 4
            str_annotation{i_ways, 1} = strcat(str_annotation{i_ways, 1}, ...
                                               ", 12 cables - 4 systems");    
        end

        % Create string if current way is DC candidate
        if data(i_ways).dc_candidate
            str_annotation{i_ways, 1} = strcat(str_annotation{i_ways, 1}, ...
                                               ", potentially DC");
        end
        
        % Add a blackspace if no annotation was made
        if isempty(str_annotation{i_ways, 1})
           str_annotation{i_ways, 1} = " "; 
            
        end
    end 

    % Create column 'Note'
    UID = [data(:).UID]';
    Note = strcat(repmat("UID: ", num_of_ways, 1), ...
                       num2str(UID, '%04.f'), string(str_annotation(:)));
            
                       
    %%% Get all the other variables needed to export "Stamm Leitungen" 
    % Get the "fromNode" and "toNode" NUIDs
    fromNode = [data(:).node1_nuid]';
    toNode = [data(:).node2_nuid]';   

    % Create column 'SpgsebeneWert'
    Voltage = [data(:).voltage]' / 1000;
            
    % Create column 'LtgLaenge', take real length if its exist, otherwise
    % beeline length
    if  isfield(data(1), 'length_real')   
        Length = [data(:).length_real]';
        fprintf(['   INFO: Real line length got used ' ...
                 '(segmentwise calculation)! \n'])
    else
        Length = [data(:).length]';
        fprintf(['   INFO: simplified line length got used ' ...
                 '(beeline - Luftlinie)! \n'])
    end
    
    % Compensate for slack
    Length = round(Length * way_length_multiplier, 2);
    
    fprintf(['   INFO: Length of each line got multiplied by %3.2f\n' ...
             '         for slack compensation! \n'], ...
             way_length_multiplier)
    
    % Create column 'LtgsID'
    LineID = [data(:).LtgsID]';
    
    % Create column 'Land'   
    Country = repmat(export_excel_country_code, num_of_ways, 1);
    
    % Create all 0-entry columns for "Stamm_Leitungen"
    [R, XL, XC, Itherm, Capacity, ...
    PhiPsMax] ...
        = deal(zeros(num_of_ways, 1));  
    
    %%% Export "Stamm_Leitungen" to Excel   
    % Create Timestamp string
    str_timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    
    % Create Countrycode string
    str_cc = [char(export_excel_country_code), '_']; 
    
    % Create table for "Stamm_Leitungen"
    table_leitungen = table(LineID, Country, fromNode, toNode,  ...
                            Voltage, R, XL, XC, Itherm, ...
                            Length, Capacity, Note, ... 
                            PhiPsMax);     
                        
    % Write that table to a Excel file                    
    writetable(table_leitungen, ...
              ['tbl_Lines_', str_cc, str_timestamp, '.xlsx'], ...
               'Sheet', 1)
           
    % Write all tags on sheet 2     
    writetable(struct2table(data_tags), ...
              ['tbl_Lines_', str_cc, str_timestamp, '.xlsx'], ...
               'Sheet', 2)
                        
    fprintf(['   INFO: In "tbl_Lines.xlsx" in  "Sheet 2" all tags ' ...
             'from all UIDs are listed! \n' ...
             '         Have a look for data inspection! \n'])
                        
         
    %%% Get all the other variables needed for export "Nodes.xlsx" 
    % Create column 'NodeID'
    NodeID = nuid;
    
    % Create column 'Country'   
    Country = repmat(export_excel_country_code, num_of_unique_nodes, 1);
    
    % Create column 'Voltage'
    Voltage = cell2mat(nodes_conversion(:, 3)) / 1000;
 
    % Create column 'lon' and 'lat'
    lon = cell2mat(nodes_conversion(:, 4));
    lat = cell2mat(nodes_conversion(:, 5));
    

    %%% Export "Nodes.xlsx" to Excel
    % Create table for "Stamm_Knoten"
    table_knoten = table(NodeID, Country, Voltage, lat, lon);
                        
    % Write that table to a Excel file                    
    writetable(table_knoten, ['tbl_Nodes_', str_cc, ...
                              str_timestamp, '.xlsx'])

    fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
end


%==========================================================================
%% Visualisation
function my_plot_ways_original(data, data_busbars, voltage_levels_selected, ...
                               bool, data_singular_ways)

    % DESCRIPTION
    % This function plots the original dataset as it was. Two plots will
    % be genereted if the flag in "bool" was set: A plot with a lon/lat
    % coordinate system and a plot with a inaccuarte, but more intuitive
    % x/y plot in km. Since Matlab is a bit tricky with legends and color
    % coding of same plots, a workaround with pseudo-points is necessary.
    % There are a total of 12 different colors which are easy
    % distinguishable. If more than 12 voltage levels will be selected,
    % colors will repeat.
    %
    % INPUT
    % data ... dataset with data to plot
    % data_busbars ... the busbars which have been deleted from data
    % voltage_levels_selected ... list of selected voltage levels to
    %                             determine color 
    % bool ... boolean operator to toggle visualisations on/off
    %
    % OUTPUT
    % (none)
    
    if bool.plot_ways_original
        tic
        disp('Start ploting original ways... (takes a few seconds)')
    
        % Create custom 12 color qualitative Colormap for better distinctness
        % Credits: Colormap based on "paired", by www.ColorBrewer.org
        colormap = [ 51,160, 44;  31,120,180; 177, 89, 40; 106, 61,154;
                    255,127,  0; 178,223,138; 227, 26, 28; 255,255,153; 
                    166,206,227; 202,178,214; 251,154,153; 253,191,111;] / 255;

        % Create a warning if colors of voltage levels do repeat
        if numel(voltage_levels_selected) > 12
            fprintf(['   ATTENTION!  More than 12 voltage levels ' ...
                                     'are selected.\n' ...
                     '               Colors of voltage lines do repeat now!'...
                     '\n               It is recommended ' ...
                     'to select max. 12 voltage levels.\n'])
        end       

        % Create figure for deg Plot
        figure
        hold on
        grid on
        title('Original ways, only selected voltages, lon/lat coordinates')
        xlabel('Longitude [°]'), ylabel('Latitude [°]')
    
        % Working around a Matlab Bug: To create concurrent coloring
        % and labeling, pseudo-points at the origin have to be plotted first
        % in the correct color order, then the legend can be created, 
        % then the pseudo points will be overwritten with white color and 
        % finally the real data can be plotted.
        
        % Calculate midpoint to place the pseudo-points
        lat_mean = mean([[data.lat1], [data.lat2]]);
        lon_mean = mean([[data.lon1], [data.lon2]]);
      
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level corresponding color
            current_color = colormap(i_colormap, :);

            % Plot pseudo-points at the origin in correct color order
            plot(lon_mean, lat_mean, 'o-' , 'Color', current_color)
        end

        % create legend labels
        labels = [num2str(flipud(voltage_levels_selected) / 1000), ...
                  repmat(' kV', numel(voltage_levels_selected), 1)];

        % Create legend in correct color order
        legend(labels, 'Location', 'northwest', 'AutoUpdate', 'off')

        % Set the pseudo-points invisible by overriding with a white point
        plot(lon_mean, lat_mean, 'o-' , 'Color', [1 1 1])
                    
        % get all coordinates of all busbars
        busbars_lon = [data_busbars.lon1; data_busbars.lon2];
        busbars_lat = [data_busbars.lat1; data_busbars.lat2];

        % Plot all busbars of current_voltage with cyan "x"
        plot(busbars_lon, busbars_lat, 'cx-', 'LineWidth', 1)   
        
        % get all coordinates of all singular ways
        singular_lon = [data_singular_ways.lon1; data_singular_ways.lon2];
        singular_lat = [data_singular_ways.lat1; data_singular_ways.lat2];

        % Plot all singular ways with black "x"
        plot(singular_lon, singular_lat, 'kx-', 'LineWidth', 1)   
            
        % Now plot the real data in correct color order, with highest vlevel
        % on top of the other voltage levels (therefore reverse for-loop)
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level a color
            current_color = colormap(i_colormap, :);

            % current voltage level in this loop:
            current_voltage = voltage_levels_selected(i_vlevel);

            % create boolean index with all wayelement in current voltage level
            b_current_voltage = [data.voltage] == current_voltage;

            % get all ways with the current voltage level
            current_ways = data(b_current_voltage);

            % get all coordinates of current ways
            lon = [current_ways.lon1; current_ways.lon2];
            lat = [current_ways.lat1; current_ways.lat2];

            % Plot all ways of current_voltage in corresponding color
            plot(lon, lat, '-o', 'Color', current_color)   
        end        

        
        % Create figure for X/Y km Plot
        figure
        hold on
        grid on
        title('Original ways, only selected voltages, x/y coordinates')
        xlabel('x - distance from midpoint [km]')
        ylabel('y - distance from midpoint [km]')
        
        % Working around a Matlab Bug: To create concurrent coloring
        % and labeling, pseudo-points at the origin have to be plotted first
        % in the correct color order, then the legend can be created, 
        % then the pseudo points will be overwritten with white color and 
        % finally the real data can be plotted.
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level corresponding color
            current_color = colormap(i_colormap, :);

            % Plot pseudo-points at the origin in correct color order
            plot([0, 0], [0, 0], 'o-' , 'Color', current_color)
        end

        % create legend labels
        labels = [num2str(flipud(voltage_levels_selected) / 1000), ...
                  repmat(' kV', numel(voltage_levels_selected), 1)];

        % Create legend in correct color order
        legend(labels, 'Location', 'northwest', 'AutoUpdate', 'off')

        % Set the pseudo-points invisible by overriding with a white point
        plot([0, 0], [0, 0], 'o-' , 'Color', [1 1 1])
                    
        % get all coordinates of all busbars
        busbars_x = [data_busbars.x1; data_busbars.x2];
        busbars_y = [data_busbars.y1; data_busbars.y2];

        % Plot all busbars/bays of current_voltage in cyan
        plot(busbars_x, busbars_y, 'cx-', 'LineWidth', 1)   
        
        % get all coordinates of all singular ways
        singular_x = [data_singular_ways.x1; data_singular_ways.x2];
        singular_y = [data_singular_ways.y1; data_singular_ways.y2];

        % Plot all singular ways with black "x" a
        plot(singular_x, singular_y, 'kx-', 'LineWidth', 1)  
        
        % Now plot the real data in correct color order, with highest vlevel
        % on top of the other voltage levels (therefore reverse for-loop)
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level a color
            current_color = colormap(i_colormap, :);

            % current voltage   level in this loop:
            current_voltage = voltage_levels_selected(i_vlevel);

            % create boolean index with all wayelement in current voltage level
            b_current_voltage = [data.voltage] == current_voltage;

            % get all ways with the current voltage level
            current_ways = data(b_current_voltage);

            % get all coordinates of current ways
            x = [current_ways.x1; current_ways.x2];
            y = [current_ways.y1; current_ways.y2];

            % Plot all ways of current_voltage in corresponding color
            plot(x, y, '-o', 'Color', current_color)      
        end  
        
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
    end
end

function my_plot_ways_grouping(data, data_busbars, grouped_xy_coordinates, ...
                               neighbourhood_threshold, bool)
                           
    % DESCRIPTION
    % This function will plot the transition while grouping endnodes. In
    % grey with dotted lines the orignal dataset will be plotted, all
    % endnodes which will be grouped together, so which are stacked or in a
    % neighourhood, will be plotted in a different color (be aware that by
    % accident neighouring neighbourhood-groups can occasionally have the
    % same colors!). Over all grouped endnodes a circle with the threshhold
    % radius will be plotted, this is very helpful to determine the correct
    % value for the treshold. If the plot reveals that obviously
    % neighbouring groups wont be grouped correctly, it is useful to
    % increase the threshold radius, the opposite is true if endnodes,
    % which should not be grouped together, will be grouped.
    %
    % INPUT
    % data ... dataset with data to plot
    % data_busbars ... the busbars which have been deleted from data
    % grouped_xy_coordinates ... all x/y coordinates of a group
    % neighbourhood_threshold ... the radius of grouping
    % bool ... boolean operator to toggle visualisations on/off
    %
    % OUTPUT
    % (none)
    
    if bool.plot_ways_grouping
        
        tic
        disp('Start plotting all grouped endnodes... (takes a few seconds)')
       
        % Start figure
        figure
        hold on
        grid on
        title('Original and final ways with grouping-circles')
        xlabel('x - distance from midpoint [km]')
        ylabel('y - distance from midpoint [km]')

        % Plot all ways dashed with all original endnodes in light grey
        x = [[data.x1]; [data.x2]];
        y = [[data.y1]; [data.y2]];      
        plot(x, y, 'o--k', 'Color', [0.6 0.6 0.6])
        
        % get all coordinates of all busbars
        busbars_lon = [data_busbars.lon1; data_busbars.lon2];
        busbars_lat = [data_busbars.lat1; data_busbars.lat2];

        % Plot all busbars of current_voltage with black "x" and crossed lines
        plot(busbars_lon, busbars_lat, 'o--', 'Color', [0.6 0.6 0.6]) 

        % Plot circles around each grouped endpoint
        origin_circles = reshape(nonzeros(grouped_xy_coordinates'), 2, [])';
        radii = neighbourhood_threshold * ones(size(origin_circles, 1), 1);
        viscircles(origin_circles, radii, 'LineWidth', 1, 'LineStyle', ':');

        % Plot the new ways
        plot([[data.x1_final]; [data.x2_final]], ...
             [[data.y1_final]; [data.y2_final]], 'k-o')

        % Plot all new grouped endpoints in pink
        x_grouped = [[data.x1_grouped],[data.x2_grouped]];
        y_grouped = [[data.y1_grouped],[data.y2_grouped]];
        plot(x_grouped, y_grouped, '.m', 'Markersize', 15)    

        % Plot all groups of combined endpoints in a different color
        for i_group = 1 : size(grouped_xy_coordinates, 1)
            group_xy = nonzeros(grouped_xy_coordinates(i_group, :));   
            
            plot(group_xy(1:2:end), group_xy(2:2:end), '*')    
        end
        
        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)           
    end
end

function my_plot_ways_final(data, voltage_levels_selected, bool)

    % DESCRIPTION
    % This function plots the final dataset as it will be exported. Two plots 
    % will be genereted if the flag in "bool" was set: A plot with a lon/lat
    % coordinate system and a plot with a inaccuarte, but more intuitive
    % x/y plot in km. Since Matlab is a bit tricky with legends and color
    % coding of same plots, a workaround with pseudo-points is necessary.
    % There are a total of 12 different colors which are easy
    % distinguishable. If more than 12 voltage levels will be selected,
    % colors will repeat.
    %
    % INPUT
    % data ... dataset with data to plot
    % voltage_levels_selected ... list of selected voltage levels to
    %                             determine color 
    % bool ... boolean operator to toggle visualisations on/off
    %
    % OUTPUT
    % (none)
    
    
    if bool.plot_ways_final   
        tic
        disp('Start ploting final ways... (takes a few seconds)')

        % Create custom 12 color qualitative Colormap for better distinctness
        % Credits: Colormap based on "paired", by www.ColorBrewer.org
        colormap = [ 51,160, 44;  31,120,180; 177, 89, 40; 106, 61,154;
                    255,127,  0; 178,223,138; 227, 26, 28; 255,255,153; 
                    166,206,227; 202,178,214; 251,154,153; 253,191,111;] / 255;

        % Create a warning if colors of voltage levels do repeat
        if numel(voltage_levels_selected) > 12
            fprintf(['   ATTENTION!  More than 12 voltage levels ' ...
                                    'are selected.\n' ...
                     '               Colors of voltage lines do repeat now!'...
                     '\n               It is recommended ' ...
                     'to select max. 12 voltage levels.\n'])
        end   
            
        %%% Create figure for degree
        figure
        hold on
        grid on
        title('Final ways as exported, lon/lat coordinates')
        xlabel('Longitude [°]'), ylabel('Latitude [°]')
    
        % Working around a Matlab Bug: To create concurrent coloring
        % and labeling, pseudo-points at the origin have to be plotted first
        % in the correct color order, then the legend can be created, 
        % then the pseudo points will be overwritten with white color and 
        % finally the real data can be plotted.
        
        % Calculate midpoint to place the pseudo-points
        lat_mean = mean([[data.lat1_final], [data.lat2_final]]);
        lon_mean = mean([[data.lon1_final], [data.lon2_final]]);
      
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level corresponding color
            current_color = colormap(i_colormap, :);

            % Plot pseudo-points at the origin in correct color order
            plot(lon_mean, lat_mean, 'o-' , 'Color', current_color)
        end

        % create legend labels
        labels = [num2str(flipud(voltage_levels_selected) / 1000), ...
                  repmat(' kV', numel(voltage_levels_selected), 1)];

        % Create legend in correct color order
        legend(labels, 'Location', 'northwest', 'AutoUpdate', 'off')

        % Set the pseudo-points invisible by overriding with a white point
        plot(lon_mean, lat_mean, 'o-' , 'Color', [1 1 1]) 
            
        % Now plot the real data in correct color order, with highest vlevel
        % on top of the other voltage levels (therefore reverse for-loop)
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level a color
            current_color = colormap(i_colormap, :);

            % current voltage level in this loop:
            current_voltage = voltage_levels_selected(i_vlevel);

            % create boolean index with all wayelement in current voltage level
            b_current_voltage = [data.voltage] == current_voltage;

            % get all ways with the current voltage level
            current_ways = data(b_current_voltage);

            % get all coordinates of current ways
            lon = [current_ways.lon1_final; current_ways.lon2_final];
            lat = [current_ways.lat1_final; current_ways.lat2_final];

            % Plot all ways of current_voltage in corresponding color
            plot(lon, lat, '-o', 'Color', current_color)   
        end        

        
        %%% Create figure for X/Y km
        figure
        hold on
        grid on
        title('Final ways as exported, x/y coordinates')
        xlabel('x - distance from midpoint [km]')
        ylabel('y - distance from midpoint [km]')
        
        % Working around a Matlab Bug: To create concurrent coloring
        % and labeling, pseudo-points at the origin have to be plotted first
        % in the correct color order, then the legend can be created, 
        % then the pseudo points will be overwritten with white color and 
        % finally the real data can be plotted.
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level corresponding color
            current_color = colormap(i_colormap, :);

            % Plot pseudo-points at the origin in correct color order
            plot([0, 0], [0, 0], 'o-' , 'Color', current_color)
        end

        % create legend labels
        labels = [num2str(flipud(voltage_levels_selected) / 1000), ...
                  repmat(' kV', numel(voltage_levels_selected), 1)];

        % Create legend in correct color order
        legend(labels, 'Location', 'northwest', 'AutoUpdate', 'off')

        % Set the pseudo-points invisible by overriding with a white point
        plot([0, 0], [0, 0], 'o-' , 'Color', [1 1 1])

            
        % Now plot the real data in correct color order, with highest vlevel
        % on top of the other voltage levels (therefore reverse for-loop)
        for i_vlevel = numel(voltage_levels_selected) : -1 : 1

            % Cycle through the indices of 1:12 even if it exceeds 12
            % e.g.: 1:12 maps to 1:12, 13:24 maps to 1:12 too, etc.
            i_colormap = i_vlevel - floor((i_vlevel-1)/12)*12;

            % Pick for each voltage level a color
            current_color = colormap(i_colormap, :);

            % current voltage level in this loop:
            current_voltage = voltage_levels_selected(i_vlevel);

            % create boolean index with all wayelement in current voltage level
            b_current_voltage = [data.voltage] == current_voltage;

            % get all ways with the current voltage level
            current_ways = data(b_current_voltage);

            % get all coordinates of current ways
            x = [current_ways.x1_final; current_ways.x2_final];
            y = [current_ways.y1_final; current_ways.y2_final];

            % Plot all ways of current_voltage in corresponding color
            plot(x, y, '-o', 'Color', current_color)      
        end  

        fprintf('   ... finished! (%5.3f seconds) \n \n', toc)
    end       
end