% Function to rename files recursively
function renameFilesRecursively(folderPath, oldText, newText)
    % Get all files inside folder (including subdirectories)
    files = dir(fullfile(folderPath, '**', '*.*')); 
    
    for k = 1:numel(files)
        oldFilePath = fullfile(files(k).folder, files(k).name);
        newFileName = strrep(files(k).name, oldText, newText);
        newFilePath = fullfile(files(k).folder, newFileName);
            
        % Ensure we rename .nii.gz, .bval, and .bvec files correctly
        if ~strcmp(oldFilePath, newFilePath)
                movefile(oldFilePath, newFilePath);
        end
    end
end
