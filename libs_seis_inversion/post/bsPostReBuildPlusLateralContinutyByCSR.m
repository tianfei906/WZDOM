function [outputData] = bsPostReBuildPlusLateralContinutyByCSR(GInvParam, GSParam, inputData, inIds, crossIds, options)

    [sampNum, traceNum] = size(inputData);


    GSParam = bsInitDLSRPkgs(GSParam, options.gamma, sampNum);

        % tackle the inverse task
    outputData = zeros(sampNum, traceNum);
    dt = GInvParam.dt;
    GInvParam.isParallel = 0;
    nTrace = length(inIds);
    
    gamma_vals = zeros(GSParam.sparsity * GSParam.ncell, nTrace);
    gamma_locs = zeros(GSParam.sparsity * GSParam.ncell, nTrace);
    
    if GInvParam.isParallel

        pbm = bsInitParforProgress(GInvParam.numWorkers, ...
            traceNum, ...
            'Rebuid data progress information', ...
            GInvParam.modelSavePath, ...
            GInvParam.isPrintBySavingFile);

        parfor iTrace = 1 : traceNum
            [gamma_vals(:, iTrace), gamma_locs(:, iTrace)] = bsGetGammaInfoOfOneTrace(GSParam, inputData(:, iTrace), inIds(iTrace), crossIds(iTrace), options);
            bsIncParforProgress(pbm, iTrace, 10000);
        end
        
        % parallel computing
        parfor iTrace = 1 : traceNum
            outputData(:, iTrace) = bsHandleOneTrace(GSParam, inputData(:, iTrace), gamma_vals(:, iTrace), gamma_locs(:, iTrace), options, dt);
            bsIncParforProgress(pbm, iTrace, 10000);
        end
        
        bsDeleteParforProgress(pbm);
        
    else
        % non-parallel computing 
        
        for iTrace = 1 : traceNum
            [gamma_vals(:, iTrace), gamma_locs(:, iTrace)] = bsGetGammaInfoOfOneTrace(GSParam, inputData(:, iTrace), inIds(iTrace), crossIds(iTrace), options);
        end
        
%         gamma_locs = round(bsFilterProfileData(gamma_locs, 0.1, 1));
%         gamma_locs(gamma_locs<0) = 1;
%         gamma_locs(gamma_locs>GSParam.nAtom) = GSParam.nAtom;
        
        for iTrace = 1 : traceNum
%             fprintf('Reconstructing the %d-th trace...\n', iTrace);
            outputData(:, iTrace) = bsHandleOneTrace(GSParam, inputData(:, iTrace), gamma_vals(:, iTrace), gamma_locs(:, iTrace), options, dt);
        end
    end
    
    figure; 
    subplot(2, 1, 1);
    imagesc(gamma_vals);
    title('非零元素的值');
    subplot(2, 1, 2);
    imagesc(gamma_locs);
    title('非零元素在字典中的位置');
    set(gcf, 'position', [102          95        1448         883]);
end

function [gamma_vals, gamma_locs] = bsGetGammaInfoOfOneTrace(GSParam, realData, x, y, options)
    ncell = GSParam.ncell;
    sizeAtom = GSParam.sizeAtom;
    patches = zeros(sizeAtom, ncell);
    rangeCoef = GSParam.rangeCoef;
    
    trainDICParam = GSParam.trainDICParam;
    
    for j = 1 : ncell
        js = GSParam.index(j);
        patches(:, j) = realData(js : js+sizeAtom-1);
    end
    
    if trainDICParam.isAddLocInfo && trainDICParam.isAddTimeInfo
        patches = [patches; ones(1, ncell) * x; ones(1, ncell) * y; 1 : ncell];
    elseif trainDICParam.isAddLocInfo
        patches = [patches; ones(1, ncell) * x; ones(1, ncell) * y;];
    elseif trainDICParam.isAddTimeInfo
        patches = [patches; 1 : ncell];
    end
    
    switch options.mode
    case {'low_high', 'seismic_high', 'residual'}
    
        switch trainDICParam.normalizationMode
            case 'feat_max_min'
                patches = (patches - GSParam.low_min_values) ./ (GSParam.low_max_values - GSParam.low_min_values);
            case 'whole_data_max_min'
                patches = (patches - rangeCoef(1, 1)) / (rangeCoef(1, 2) - rangeCoef(1, 1));
%             case 'patch_mean_norm'
%                 mean_vlaues = norm(patches, 1);
%                 mean_vlaues = repmat(mean_vlaues, sizeAtom, 1);
%                 patches = (patches - min_values) ./ (max_values - min_values);
        end
        
    end
        
    if trainDICParam.feature_reduction
        patches = GSParam.output.B' * patches;
    end
    
    gammas = omp(GSParam.D1'*patches, ...
                    GSParam.omp_G, ...
                    GSParam.sparsity);
            
    gamma_vals = zeros(GSParam.sparsity*ncell, 1);
    gamma_locs = zeros(GSParam.sparsity*ncell, 1) - 1;
    
    sPos = 1;
    for i = 1 : ncell
        
        index = find(gammas(:, i) ~= 0);
        ePos = sPos + length(index) - 1;
        
        gamma_vals(sPos:ePos) = gammas(index, i);
        gamma_locs(sPos:ePos) = index;
        
        sPos = sPos + GSParam.sparsity;
    end

end

function newData = bsHandleOneTrace(GSParam, realData, gamma_vals, gamma_locs, options, dt)

    sampNum = size(realData, 1);
    rangeCoef = GSParam.rangeCoef;
    
    trainDICParam = GSParam.trainDICParam;
    
    gammas = zeros(GSParam.nAtom, GSParam.ncell);

    k = 1;
    for i = 1 : GSParam.ncell
        
        for j = 1 : GSParam.sparsity
            if(gamma_locs(k) ~= -1)
                gammas(gamma_locs(k), i) = gamma_vals(i);
            end
            
            k = k + 1;
        end
        
    end
    
    gammas = sparse(gammas);
    
    new_patches = GSParam.D2 *  gammas;
    switch options.mode
    case {'low_high', 'seismic_high', 'residual'}
        
        switch trainDICParam.normalizationMode
            case 'feat_max_min'
                new_patches = new_patches .* (GSParam.high_max_values - GSParam.high_min_values) + GSParam.high_min_values; 
            case 'whole_data_max_min'
                new_patches = new_patches .* (rangeCoef(2, 2) - rangeCoef(2, 1)) + rangeCoef(2, 1); 
        end
        
    end

    tmpData = bsAvgPatches(new_patches, GSParam.index, sampNum);
    
    % 合并低频和中低频
    switch options.mode
        case {'low_high', 'seismic_high'}

            ft = 1/dt*1000/2;
            newData = bsMixTwoSignal(realData, tmpData, options.lowCut*ft, options.lowCut*ft, dt/1000);
%         bsShowFFTResultsComparison(1, [realData, tmpData, newData], {'反演结果', '高频', '合并'});
        case {'full_freq'}
            newData = tmpData;
        case 'residual'
            newData = tmpData + realData;
    end
    
end



function GSParam = bsInitDLSRPkgs(GSParam, gamma, sampNum)

    validatestring(string(GSParam.reconstructType), {'equation', 'simpleAvg'});
    
    sizeAtom = GSParam.trainDICParam.sizeAtom;
    nAtom = GSParam.trainDICParam.nAtom;

    
    GSParam.sizeAtom = sizeAtom;
    GSParam.nAtom = nAtom;
    GSParam.nrepeat = sizeAtom - GSParam.stride;
    
    index = 1 : GSParam.stride : sampNum - sizeAtom + 1;
    if(index(end) ~= sampNum - sizeAtom + 1)
        index = [index, sampNum - sizeAtom + 1];
    end
    
    GSParam.index = index;
    GSParam.ncell = length(index);
    [GSParam.R] = bsCreateRMatrix(index, sizeAtom, sampNum);
   
    tmp = zeros(sampNum, sampNum);
    for iCell = 1 : GSParam.ncell
        tmp = tmp + GSParam.R{iCell}' * GSParam.R{iCell};
    end
    GSParam.invTmp = tmp;
    GSParam.invR = inv(gamma * eye(sampNum) + GSParam.invTmp);
    
    % 低分辨率patch可能有时间和地址信息
    n1 = size(GSParam.DIC, 1) - sizeAtom;
    
    D1 = GSParam.DIC(1:n1, :);
    D2 = GSParam.DIC(n1+1:end, :);
    
    [D1, D2, C] = bsNormalDIC(D1, D2);
    
    GSParam.D1 = D1;
    
    GSParam.omp_G = D1' * D1;
    GSParam.D2 = D2;
    GSParam.C = C;
    
%     GSParam.neiborIndecies = bsGetNeiborIndecies(D1, GSParam.nNeibor);
    rangeCoef = GSParam.rangeCoef;
    
    GSParam.low_min_values = repmat(rangeCoef{1}(:, 1), 1, GSParam.ncell);
    GSParam.low_max_values = repmat(rangeCoef{1}(:, 2), 1, GSParam.ncell);
                
    GSParam.high_min_values = repmat(rangeCoef{2}(:, 1), 1, GSParam.ncell);
    GSParam.high_max_values = repmat(rangeCoef{2}(:, 2), 1, GSParam.ncell);
end

function [D1, D2, C] = bsNormalDIC(D1, D2)
    C = zeros(size(D1, 2), 1);
    
    for i = 1 : size(D1, 2)
        normCoef = norm(D1(:, i));
        D1(:, i) = D1(:, i) / normCoef;
        D2(:, i) = D2(:, i) / normCoef;
        C(i) = normCoef;
    end
end
  