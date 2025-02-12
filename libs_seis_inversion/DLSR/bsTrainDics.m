function [DIC, trainIndex, rangeCoef, output] = bsTrainDics(GTrainDICParam, trueModel, trainIndex, attIndex)
%% This function is used to learn one dictionary from given model
% Programmed by: Bin She (Email: bin.stepbystep@gmail.com)
% Programming dates: Nov 2019
% -------------------------------------------------------------------------
    
    % create a folder to save the trained dictionary
    if ~exist(GTrainDICParam.dicSavePath, 'dir')
       mkdir(GTrainDICParam.dicSavePath);
    end
    
    % get the number of train wells
    trueModel = trueModel(:, trainIndex);
    trainNum = length(trainIndex);
    
    %% set a file name automatically based on the trianing parameter and stop the training
    % progress if the file already exits
    fileName = sprintf('%s/DIC_%s_%s_nTrain_%d_sAtom_%d_nAtom_%d_filt_%.2f_normal_%s_addTime_%d_addLoc_%d_feat_reduce_%s.mat', ...
            GTrainDICParam.dicSavePath, ...
            GTrainDICParam.flag, ...
            GTrainDICParam.title, ...
            trainNum, ...
            GTrainDICParam.sizeAtom, ...
            GTrainDICParam.nAtom, ...
            GTrainDICParam.filtCoef, ...
            GTrainDICParam.normalizationMode, ...
            GTrainDICParam.isAddTimeInfo, ...
            GTrainDICParam.isAddLocInfo, ...
            GTrainDICParam.feature_reduction ...
        );
    
    
    if exist(fileName, 'file') && GTrainDICParam.isRebuild==0
       res = load(fileName);
       DIC = res.DIC;
       trainIndex = res.trainIndex;
       rangeCoef = res.rangeCoef;
       output = res.output;
       return;
    end
    
    %% cut the welllog data into pieces and train a dictionary
%     GTrainDICParam.iterNum = 5; 
    nAtt = length(attIndex);
    rangeCoef = [];
    output = [];
    
    
    switch lower(GTrainDICParam.flag)
        case {'one', 'ssr'}
            DIC = cell(1, nAtt);
            for k = 1 : nAtt
                trainLogs = cell(1, trainNum);
                xs = zeros(1, trainNum);
                ys = zeros(1, trainNum);
            
                for i = 1 : trainNum
                    trainLogs{i} = trueModel{i}.wellLog(:, attIndex(k));
                    xs(i) = trueModel{i}.inline;
                    ys(i) = trueModel{i}.crossline;
                end
             
                % learn dictionary 
                [DIC{k}, rangeCoef, output] = bsTrain1DSparseDIC(trainLogs, GTrainDICParam, xs, ys);
            end
            
            if strcmpi(GTrainDICParam.flag, 'one')
                % only one dictionary
                DIC = DIC{1};
            end
            
        case 'csr'
            trainLogs = cell(1, trainNum);
            xs = zeros(1, trainNum);
            ys = zeros(1, trainNum);
            
            for i = 1 : trainNum
                trainLogs{i} = trueModel{i}.wellLog(:, attIndex);
                xs(i) = trueModel{i}.inline;
                ys(i) = trueModel{i}.crossline;
            end
            [DIC, rangeCoef, output] = bsTrain1DSparseJointDIC(trainLogs, GTrainDICParam, xs, ys);
            
            
        case 'dual'
            trainLogs = cell(1, trainNum);
            for i = 1 : trainNum
                trainLogs{i} = trueModel{i}.wellLog(:, attIndex);
            end
            
            DIC = bsTrain1DSparseDualDIC(trainLogs, GTrainDICParam);
            
    end
    
    save(fileName, 'DIC', 'trainIndex', 'rangeCoef', 'output');
    % save the results
    
        
end