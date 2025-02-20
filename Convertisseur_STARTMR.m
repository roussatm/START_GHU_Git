% Drive directory
Drive_dir = '/media/madyroussat/Expansion/START_images_dicom/';
Orga_dir = '/media/madyroussat/Expansion/START_organized';

% Add SPM to the path
spmPath = '/home/madyroussat/Documents/Software/';
if exist(spmPath, 'dir')
    addpath(spmPath);
else
    error('SPM not found');
end

% Path to the Excel file for START identifiers
excelFile = '/home/madyroussat/Documents/GHU/START/Fichiers_suivi/ListeImagerieSTART_MR.xlsx';

% DCM2niix path
dcm2niixPath = '/home/madyroussat/Documents/Software/dcm2niix';

% Read the Excel file (specific columns for matching patient names and IDs)
[~, ~, rawData] = xlsread(excelFile);
headers = rawData(1, :);  % Assuming the first row contains headers
M0ColIdx = find(strcmp(headers, 'START_identifiant_imagerie_M0')); % Find the column for M0 ID
MFColIdx = find(strcmp(headers, 'START_identifiant_imagerie_MF')); % Find the column for MF ID
STARTCodeColIdx = find(strcmp(headers, 'START_code')); % Find the column for START code
STARTGroupeColIdx = find(strcmp(headers, 'START_groupe')); % Find group columns

% Initialize cell array to hold the file paths
dcmlist = {};

% Loop through the directories 'repertoire_1' to 'repertoire_6'
for i = 2:2
    folderPath = fullfile(Drive_dir, sprintf('repertoire_%d', i));
    if exist(folderPath, 'dir')
        % Get all files matching 'IM0*' recursively in the current directory
        files = spm_select('FPListRec', folderPath, 'IM0');  % Recursive search for IM0*

        % If files are found, append them to dcmlist
        if ~isempty(files)
            dcmlist = [dcmlist; cellstr(files)];  % Convert to cell array and append
        end
    end
end

% Ensure the list is not empty
if isempty(dcmlist)
    error('No matching files found');
end

% Read the DICOM headers
info = spm_dicom_headers(dcmlist);

% Create a table to store the extracted information
infoTable = table('Size', [0 10], ...
    'VariableTypes', {'string', 'string', 'string', 'string', 'string', 'string', 'string', 'string', 'string', 'string'}, ...
    'VariableNames', {'START_ID', 'IRM_ID', 'PatientSex', 'PatientAge', 'PatientGroup', 'Date',  'SeriesDescription', 'FilePath', 'DICOMCount', 'NewDirectory'});

% Open log file for writing
logFile = fullfile(Orga_dir, 'conversion_log.txt');
fid = fopen(logFile, 'w');

% Loop through the headers to extract information
for i = 1:numel(info)
    hdr = info{i};
    studyDesc = getFieldSafe(hdr, 'StudyDescription', '');
    seriesDesc = getFieldSafe(hdr, 'SeriesDescription', '');
    
    % Trim leading/trailing spaces and remove internal spaces for seriesDesc
    if ~isempty(seriesDesc)
        seriesDesc = strtrim(seriesDesc);          % Remove leading/trailing spaces
        seriesDesc = strrep(seriesDesc, ' ', '_'); % Replace internal spaces with underscores
    end

    patientName = getFieldSafe(hdr, 'PatientName', '');
    patientSex = getFieldSafe(hdr, 'PatientSex', '');
    patientAge = getFieldSafe(hdr, 'PatientAge', '');
    
    % Trim leading/trailing spaces and remove internal spaces for patientName
    patientName = strtrim(patientName);          % Trim leading/trailing spaces
    patientName = strrep(patientName, ' ', '');  % Remove internal spaces (replace with nothing)
    
    % Convert patientName to uppercase (majuscules)
    patientName = upper(patientName);
    
    if ~isempty(patientName) && strlength(patientName) > 8
        patientName = extractBefore(patientName, 9);  % Extract first 8 characters
    end
   
    % List of patient names to skip
    skipPatients = {'CA201177', 'VI201210', 'DL180904', 'LC180988', 'RA170836', 'RC180966', 'LC160504'};
    
    % Check if patientName is in the list of patients to skip
    if ismember(patientName, skipPatients)
        fprintf('Skipping Patient %s, directory %s not converted\n', patientName, dcmlist{i});
        continue;  % Skip to the next iteration of the loop
    end

    % Extract and format the exam date (in dicom headers StudyDate)
    studyDate = getFieldSafe(hdr, 'StudyDate', '');
    Date = ''; % Initialize as empty
    if ~isempty(studyDate)
        try
            % Readable format
            Date = datestr(studyDate, 'yyyy-mm-dd');
        catch
            Date = 'InvalidDate'; % Fallback if conversion fails
        end
    end

    % Format PatientAge (keep it as only a number)
    if ~isempty(patientAge) && strlength(patientAge) == 4
        patientAge = extractBetween(patientAge, 2, 3);
    end

    % Convert file path to string
    filePath = string(dcmlist{i});
    
    % Default values
    START_ID = 'Not Found';
    PatientGroup = 'Unknown';  % Default value in case no match is found
    foundInColumns = 0;
    
    for row = 2:size(rawData, 1)  % Assuming the first row is the header
        % Check if patientName matches M0 column
        if strcmpi(rawData{row, M0ColIdx}, patientName)
            foundInColumns = foundInColumns + 1;
        end
        
        % Check if patientName matches MF column
        if strcmpi(rawData{row, MFColIdx}, patientName)
            foundInColumns = foundInColumns + 1;
        end
        
        % If patientName appears in both columns, display error and stop
        if foundInColumns > 1
            error('Error: Patient name appears in both M0 and MF columns.');
        end
        
        % Retrieve START_ID if match found
        if foundInColumns > 0
            START_ID = rawData{row, STARTCodeColIdx};
    
            % Ensure STARTGroupeColIdx exists before accessing
            if ~isempty(STARTGroupeColIdx)
                PatientGroup = rawData{row, STARTGroupeColIdx};
            else
                PatientGroup = 'Unknown'; % Fallback if column is missing
            end
            break;
        end
    end

    % Define subject directory
    subjectDir = fullfile(Orga_dir, sprintf('sub-%s', START_ID));
        if ~exist(subjectDir, 'dir')
            mkdir(subjectDir);
        end
    
    % Check for existing sessions
    sessionNumber = 1;
    isMatchFound = false;  % Flag to indicate if a match is found
    
    if exist(subjectDir, 'dir')
        existingSessions = dir(fullfile(subjectDir, 'ses-*'));
        
        if ~isempty(existingSessions)
            existingSessionNames = {existingSessions.name};
            matchIdx = contains(existingSessionNames, patientName);  % Check for matching session names
            matchedIndices = find(matchIdx);  % Indices where patientName is part of the session name
            unmatchedIndices = find(~matchIdx);  % Indices where patientName is NOT part of the session name
    
            if ~isempty(matchedIndices)
                % Extract the first matched session folder
                existingSessionFolder = existingSessionNames{matchedIndices(1)};
                
                % Extract patient ID from the session folder name
                existingPatientID = extractAfter(existingSessionFolder, 'ses-');
                existingPatientID = extractAfter(existingPatientID, '-');  % Get only the ID part
    
                % If patient ID matches, continue with that folder
                if strcmp(existingPatientID, patientName)
                    % Extract session number from folder name (e.g., ses-01)
                    sessionNumber = str2double(extractBetween(existingSessionFolder, 'ses-', '-'));
                    fprintf('Existing session detected for %s: %s\n', patientName, existingSessionFolder);
                    
                    isMatchFound = true;  % Set flag to true, indicating a match is found
                end
            end
            
            % Handle unmatched session names, only if no match was found
            if ~isMatchFound && ~isempty(unmatchedIndices)
                % Extract the first unmatched session folder
                existingSessionFolder = existingSessionNames{unmatchedIndices(1)};
                existingPatientID = extractAfter(existingSessionFolder, 'ses-');
                existingPatientID = extractAfter(existingPatientID, '-');  % Get only the ID part
                
                % Compare years from patient IDs (Characters 3 & 4)
                existingYear = str2double(existingPatientID(3:4));
                currentYear = str2double(patientName(3:4));
    
                if existingYear < currentYear
                    sessionNumber = 2;  % Assign session 2 if the existing session is older
                else
                    % Rename the session folder to ses-02
                    movefile(fullfile(subjectDir, existingSessionFolder), fullfile(subjectDir, sprintf('ses-02-%s', existingPatientID)));
                    renameFilesRecursively(fullfile(subjectDir, sprintf('ses-02-%s', existingPatientID)), 'ses-01', 'ses-02');
                    sessionNumber = 1;
                end
            end
        end
    
    % Create session directory
    sessionDir = fullfile(subjectDir, sprintf('ses-0%d-%s', sessionNumber, patientName));
    if ~exist(sessionDir, 'dir')
        mkdir(sessionDir);
    end
        
    % Determine output directory and filename based on SeriesDescription
    switch seriesDesc
        case '3DT1'
            category = 'anat';
            filePrefix = sprintf('sub-%s_ses-0%d_T1w', patientName, sessionNumber);
            
        case 'T2_FLAIR_FS_3,5mm'
            category = 'anat';
            filePrefix = sprintf('sub-%s_ses-0%d_FLAIR', patientName, sessionNumber);
            
        case 'Part1_Run1'
            category = 'func';
            filePrefix = sprintf('sub-%s_ses-0%d_task-self_run-01_bold', patientName, sessionNumber);
            
        case 'Part1_Run1bis'
            category = 'func';
            filePrefix = sprintf('sub-%s_ses-0%d_task-self_run-01bis_bold', patientName, sessionNumber);
            
        case 'Part1_Run2'
            category = 'func';
            filePrefix = sprintf('sub-%s_ses-0%d_task-self_run-02_bold', patientName, sessionNumber);
            
        case 'Part1_Run2bis'
            category = 'func';
            filePrefix = sprintf('sub-%s_ses-0%d_task-self_run-02bis_bold', patientName, sessionNumber);
            
        case 'Average_DC'
            category = 'dwi';
            filePrefix = sprintf('sub-%s_ses-0%d_%s', patientName, sessionNumber, seriesDesc);
            
        case 'DTI'
            category = 'dwi';
            filePrefix = sprintf('sub-%s_ses-0%d_dwi', patientName, sessionNumber);
            
        case 'Fractional_Aniso.'
            category = 'dwi';
            filePrefix = sprintf('sub-%s_ses-0%d_%s', patientName, sessionNumber, seriesDesc);
            
        case 'Isotropic_image'
            category = 'dwi';
            filePrefix = sprintf('sub-%s_ses-0%d_%s', patientName, sessionNumber, seriesDesc);
            
        case 'Trace:Apr_04_2019_17-03-20'
            category = 'dwi';
            filePrefix = sprintf('sub-%s_ses-0%d_%s', patientName, sessionNumber, seriesDesc);
            
        case 'rsfMRI'
            category = 'func';
            filePrefix = sprintf('sub-%s_ses-0%d_task-rest_run-01_bold', patientName, sessionNumber);
            
        case {'Carte_Phase_TE_4.92','Carte_Phase_TE_4.92_3mm_42coupes', 'Carte_Phase_TE_7.00_3mm_42coupes', 'Carte_Phase_TE_7.38', 'Ph_inv_rsfMRI_pepolar_0', 'Ph_inv_rsfMRI_pepolar_1', 'Ph_inv_Runs_pepolar_1_asset1', 'Ph_inv_Runs_pepolar0_asset_2', 'Ph_inv_Runs_pepolar0_asset1', 'Ph_inv_Runs_pepolar1_asset_2', 'Ph_inv_Runs_pepolar1asset_2', 'Ph_inverse_DTI', 'ph_inverse_rsfMRI', 'Phase_inverse_1', 'Phase_inverse_2'}  
            category = 'fmap';
            filePrefix = sprintf('sub-%s_ses-0%d_%s', patientName, sessionNumber, seriesDesc);
            
        otherwise
            fprintf('Serie %s not useful, so not converted\n', seriesDesc);
    end

    % Define output directory
    outputDir = fullfile(sessionDir, category);
    
    % Ensure the output directory exists
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % Get list of all existing files in the output directory
    existingFiles = dir(fullfile(outputDir, sprintf('%s*.nii.gz', filePrefix)));
    existingNames = arrayfun(@(x) erase(x.name, '.nii.gz'), existingFiles, 'UniformOutput', false);
    
    % Initialize counter
    fileNumber = 1;
    baseFileName = sprintf('%s.nii.gz', filePrefix);
    outputFilepath = fullfile(outputDir, baseFileName);
    
    % If the file exists, increment with _2, _3, etc.
    while any(strcmp(existingNames, erase(baseFileName, '.nii.gz')))
        fileNumber = fileNumber + 1;
        baseFileName = sprintf('%s_%d.nii.gz', filePrefix, fileNumber);
        outputFilepath = fullfile(outputDir, baseFileName);
    end
    
    % Apply the same rule for associated files (DWI case)
    if contains(category, 'dwi')
        bvalFilename = fullfile(outputDir, strrep(baseFileName, '.nii.gz', '.bval'));
        bvecFilename = fullfile(outputDir, strrep(baseFileName, '.nii.gz', '.bvec'));
    
        % Ensure uniqueness for .bval and .bvec too
        while exist(bvalFilename, 'file') || exist(bvecFilename, 'file') || exist(outputFilepath, 'file')
            fileNumber = fileNumber + 1;
            baseFileName = sprintf('%s_%d.nii.gz', filePrefix, fileNumber);
            outputFilepath = fullfile(outputDir, baseFileName);
            bvalFilename = fullfile(outputDir, strrep(baseFileName, '.nii.gz', '.bval'));
            bvecFilename = fullfile(outputDir, strrep(baseFileName, '.nii.gz', '.bvec'));
        end
    end
    
    % Ensure dicomFolder is a valid string
    dicomFolder = fileparts(string(dcmlist{i}));
    
    % Check if the folder exists before calling dir()
    if isempty(dicomFolder) || ~isfolder(dicomFolder)
        warning('DICOM folder not found: %s', dicomFolder);
        continue; % Skip this iteration if the folder is missing
    end
    
    % Get list of DICOM files
    dicomFiles = dir(char(fullfile(dicomFolder, '*'))); % Ensure correct input type
    dicomCount = numel(dicomFiles) - 2;  % Exclude '.' and '..'
    
    % Remove .nii.gz before passing to dcm2niix
    baseFileNameWithoutExt = erase(baseFileName, '.nii.gz');
    
    % Format the dcm2niix command (-z for compressed and -m to merge)
    dcm2niixCommand = sprintf('"%s" -z y -m y -f "%s" -o "%s" "%s"', ...
        dcm2niixPath, baseFileNameWithoutExt, outputDir, dicomFolder);
    
    % Debugging print statement
    disp(['Executing command: ', dcm2niixCommand]);
    fprintf(fid, 'Executing command: %s\n', dcm2niixCommand);
    
    % Run the system command
    status = system(dcm2niixCommand);

    % Check if conversion was successful
    if status == 0
        newDirectory = outputFilepath;
        fprintf('Successfully converted: %s\n', outputFilepath);
        fprintf(fid, 'Successfully converted: %s\n', outputFilepath);
    else
        newDirectory = 'ConversionFailed';
        warning('Failed to convert: %s\n', outputFilepath);
        fprintf(fid, 'Failed to convert: %s\n', outputFilepath);
    end

    % Append to the table with the new directory column
    newRow = {START_ID, patientName, patientSex, patientAge, PatientGroup, Date, seriesDesc, dcmlist{i}, dicomCount, newDirectory};
    infoTable = [infoTable; newRow];
end
end 

% Close log file
fclose(fid);

% Display the table
disp(infoTable);

% Save the table as an Excel file
%outputFile = fullfile(Orga_dir, 'Conversion_test.xlsx');
%writetable(infoTable, outputFile, 'FileType', 'spreadsheet');
%disp(['File saved at: ', outputFile]);

