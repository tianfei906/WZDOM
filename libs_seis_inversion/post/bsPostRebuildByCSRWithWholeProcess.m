function outResult = bsPostRebuildByCSRWithWholeProcess(GInvParam, timeLine, wellLogs, invResult, name, varargin)

    p = inputParser;
    GTrainDICParam = bsCreateGTrainDICParam(...
        'csr', ...
        'title', '', ...
        'sizeAtom', 90, ...
        'sparsity', 5, ...
        'iterNum', 5, ...
        'nAtom', 4000, ...
        'filtCoef', 1);
    
    is3D = length(invResult.inIds) > 5000;
    
    addParameter(p, 'ratio_to_reconstruction', '1');
    addParameter(p, 'mode', 'low_high');
    addParameter(p, 'nNeibor', '2');
    addParameter(p, 'isSaveSegy', '1');

    % 相邻多个块同时稀疏表示的个数
    addParameter(p, 'nMultipleTrace', 1);
    
    addParameter(p, 'lowCut', 0.1);
    addParameter(p, 'highCut', 1);
    addParameter(p, 'sparsity', 5);
    addParameter(p, 'gamma', 0.5);
    addParameter(p, 'is3D', is3D);
    
    addParameter(p, 'wellFiltCoef', 0.1);
    addParameter(p, 'title', 'HLF');
    addParameter(p, 'trainNum', length(wellLogs));
    addParameter(p, 'exception', []);
    addParameter(p, 'mustInclude', []);
    addParameter(p, 'isInterpolation', 0);
    addParameter(p, 'GTrainDICParam', GTrainDICParam);
    
    addParameter(p, 'invDataAtWellLocation', []);
    
    if is3D
        addParameter(p, 'gst_options', bsCreateGSTParam(3));
    else
        addParameter(p, 'gst_options', bsCreateGSTParam(2));
    end
    
    p.parse(varargin{:});  
    options = p.Results;
    GTrainDICParam = options.GTrainDICParam;
    GTrainDICParam.filtCoef = 1;
    
    switch options.mode
        case 'full_freq'
            GTrainDICParam.normailzationMode = 'off';
            GTrainDICParam.title = sprintf('%s_highCut_%.2f', ...
                GTrainDICParam.title, options.highCut);
        case 'low_high'
%             GTrainDICParam.normailzationMode = 'whole_data_max_min';
            options.gamma = 1;
            GTrainDICParam.title = sprintf('%s_lowCut_%.2f_highCut_%.2f', ...
                GTrainDICParam.title, options.lowCut, options.highCut);
        case 'seismic_high'
            GTrainDICParam.normailzationMode = 'whole_data_max_min';
            options.gamma = 1;
            GTrainDICParam.title = sprintf('%s_seismic_lowCut_%.2f_highCut_%.2f', ...
                GTrainDICParam.title, options.lowCut, options.highCut);
        case 'residual'
            GTrainDICParam.normailzationMode = 'whole_data_max_min';
            options.gamma = 1;
            GTrainDICParam.title = sprintf('%s_residual_lowCut_%.2f', ...
                GTrainDICParam.title, options.lowCut);
    end
    
    if isempty(options.invDataAtWellLocation)
        % 如果测井位置的反演结果没有给出，则从反演结果中搜索过井的数据
        [wellPos, wellIndex, wellNames] = bsFindWellLocation(wellLogs, invResult.inIds, invResult.crossIds);
        names = join(wellNames, ',');
        try
            fprintf('反演结果中检测到共%d道过井，分别为:\n\tinIds:%s...\n\tcrossIds:%s\n\twellNames=%s\n', ...
                length(wellPos), ...
                mat2str(invResult.inIds(wellPos)), ...
                mat2str(invResult.crossIds(wellPos)), ...
                names{1});

            wellLogs = wellLogs(wellIndex);
        catch
            error('There is no wells in the inverted data!!!');
        end

        try
            set_diff = setdiff(1:length(wellPos), options.exception);
            train_ids = bsRandSeq(set_diff, options.trainNum);
            train_ids = unique([train_ids, options.mustInclude]);

        catch
            options.trainNum = length(wellPos);
            train_ids = 1 : length(wellPos);
        end

        [outLogs] = bsGetPairOfInvAndWell(GInvParam, timeLine, wellLogs, invResult.data(:, wellPos), GInvParam.indexInWellData.ip, options);
    else
        % 相反，则直接运用给定的options.invDataAtWellLocation来训练字典
        options.trainNum = length(wellLogs);
        train_ids = 1 : length(wellLogs);
        
        assert(size(options.invDataAtWellLocation, 2) == length(wellLogs), '训练井的数量应该与其对应的反演结果道数一致');
        [outLogs] = bsGetPairOfInvAndWell(GInvParam, timeLine, wellLogs, options.invDataAtWellLocation, GInvParam.indexInWellData.ip, options);
    end
%     bsShowFFTResultsComparison(GInvParam.dt, outLogs{1}.wellLog, {'反演结果', '联合字典配对'});

%     bsShowWellLogs(outLogs([2, 5,9]), 4, [1], {'I_P'}, 'colors', {'r'});
%     set(gcf, 'position', [718   180   676   394]);
%     bsShowWellLogs(outLogs([2, 5,9]), 4, [3], {'High-freq'}, 'colors', {'k'});
%     set(gcf, 'position', [718   180   676   394]);
    
    %% 训练字典
    fprintf('训练联合字典中...\n');
    
    
    if ~options.isInterpolation
        [DIC, train_ids, rangeCoef, output] = bsTrainDics(GTrainDICParam, outLogs, train_ids, [ 1, 2]);
        GInvWellSparse = bsCreateGSparseInvParam(DIC, GTrainDICParam, ...
        'sparsity', options.sparsity, ...
        'nNeibor', options.nNeibor, ...
        'stride', 1);
        GInvWellSparse.rangeCoef = rangeCoef;
        GInvWellSparse.output = output;
    else
        GTrainDICParam.isRebuild = 0;
    end
    
    
%     options.rangeCoef = rangeCoef;
%     [testData] = bsPostReBuildByCSR(GInvParam, GInvWellSparse, wellInvResults{1}.data, options);
    
%     figure; plot(testData(:, 1), 'r', 'linewidth', 2); hold on; 
%     plot(outLogs{1}.wellLog(:, 2), 'k', 'linewidth', 2); 
%     plot(outLogs{1}.wellLog(:, 1), 'b', 'linewidth', 2);
%     legend('重构结果', '实际测井', '反演结果', 'fontsize', 11);
%     set(gcf, 'position', [261   558   979   420]);
%     bsShowFFTResultsComparison(GInvParam.dt, [outLogs{10}.wellLog, testData(:, 10)], {'反演结果', '实际测井', '高分辨率反演结构'});
    
    %% 联合字典稀疏重构
    fprintf('联合字典稀疏重构: 参考数据为反演结果...\n');
    
%     switch options.mode
%         case {'full_freq', 'low_high', 'residual'}
%             inputData = invResult.data;
%         case 'seismic_high'
%             startTime = invResult.horizon - GInvParam.upNum * GInvParam.dt;
%             sampNum = GInvParam.upNum + GInvParam.downNum;
%             inputData = bsGetPostSeisData(GInvParam, invResult.inIds, invResult.crossIds, startTime, sampNum);
%     end
    startTime = invResult.horizon - GInvParam.upNum * GInvParam.dt;
    sampNum = GInvParam.upNum + GInvParam.downNum;
    inputData = bsGetPostSeisData(GInvParam, invResult.inIds, invResult.crossIds, startTime, sampNum);
%     [wellPos, wellIndex, wellNames] = bsFindWellLocation(wellLogs, invResult.inIds, invResult.crossIds);
    
    if ~options.isInterpolation
%         if options.nMultipleTrace <= 1
%             [outputData, highData] = bsPostReBuildPlusInterpolationCSR(GInvParam, GInvWellSparse, invResult.data, inputData, invResult.inIds, invResult.crossIds, options);
%         else
        [outputData, highData] = bsPostReBuildMulTraceCSR(GInvParam, GInvWellSparse, invResult.data, inputData, invResult.inIds, invResult.crossIds, options);
%         end
    else
        [outputData, highData] = bsPostReBuildInterpolation(GInvParam, outLogs(train_ids), invResult.data, invResult.inIds, invResult.crossIds, options);
    end
    
    
    outResult = bsSetFields(invResult, {'data', outputData; 'name', name; 'highData', highData; 'train_ids', train_ids});
    
    if options.isSaveSegy                    
        bsWriteInvResultsIntoSegyFiles(GInvParam, {outResult}, options.title);
    end
end