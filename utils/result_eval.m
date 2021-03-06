function miss = result_eval(conf,aboxes,model_stage,imdb,roidb,cachedir)
%% Evaluation
% init log
cache_dir = fullfile(pwd, 'output', conf.exp_name, cachedir, model_stage.cache_name, imdb.name);
timestamp = datestr(datevec(now()), 'yyyymmdd_HHMMSS');
mkdir_if_missing(fullfile(cache_dir, 'log'));
log_file = fullfile(cache_dir, 'log', ['eval_', timestamp, '.txt']);
diary(log_file);

%% nms
fprintf('Doing nms ... \n');                                
aboxes                      = boxes_filter(aboxes, model_stage.nms.per_nms_topN, model_stage.nms.nms_overlap_thres, model_stage.nms.after_nms_topN, conf.use_gpu);      

%% eval the gt recall
gt_num = 0;
gt_re_num = 0;
for i = 1:length(roidb.rois)
    gts = roidb.rois(i).boxes(roidb.rois(i).ignores~=1, :);
    if ~isempty(gts)
        rois = aboxes{i}(:, 1:4);
        max_ols = max(boxoverlap(rois, gts));
        gt_num = gt_num + size(gts, 1);
        gt_re_num = gt_re_num + sum(max_ols >= 0.5);
    end
end
fprintf('gt recall rate = %.4f\n', gt_re_num / gt_num);
%% output the results
fprintf('Preparing the results for evaluation ...');
res_boxes = aboxes;
mkdir_if_missing(fullfile(cache_dir, conf.method_name));
% remove all the former results
DIRS=dir(fullfile(fullfile(cache_dir, conf.method_name))); 
n=length(DIRS);
for i=1:n
    if (DIRS(i).isdir && ~strcmp(DIRS(i).name,'.') && ~strcmp(DIRS(i).name,'..') ) % except . ..
        rmdir(fullfile(cache_dir, conf.method_name ,DIRS(i).name),'s'); % remove include subdir
    end
end
assert(length(imdb.image_ids) == size(res_boxes, 1));
bbsNm = fullfile(cache_dir, [conf.method_name '_Det.txt']);
if(exist(bbsNm,'file')), delete(bbsNm); end
fid2 = fopen(bbsNm, 'w');
for i = 1:size(res_boxes, 1)
    if ~isempty(res_boxes{i})
        sstr = strsplit(imdb.image_ids{i}, '_');
        mkdir_if_missing(fullfile(cache_dir, conf.method_name, sstr{1}));
        fid = fopen(fullfile(cache_dir, conf.method_name, sstr{1}, [sstr{2} '.txt']), 'a');
        % transform [x1 y1 x2 y2] to [x y w h], for matching the
        % evaluation protocol
        res_boxes{i}(:, 3) = res_boxes{i}(:, 3) - res_boxes{i}(:, 1); % h
        res_boxes{i}(:, 4) = res_boxes{i}(:, 4) - res_boxes{i}(:, 2); % w
        for j = 1:size(res_boxes{i}, 1)
            fprintf(fid, '%d,%f,%f,%f,%f,%f\n', str2double(sstr{3}(2:end))+1, res_boxes{i}(j, :)); % dirs result
            fprintf(fid2, '%d,%.2f,%.2f,%.2f,%.2f,%.2f\n', i,  res_boxes{i}(j, :)); % one file
        end
        fclose(fid);
    end
end
fclose(fid2);
fprintf('Done.');

% run evaluation using bbGt
[gt,dt] = bbGt('loadAll',roidb.anno_path,bbsNm,conf.eval_pLoad);
[gt,dt] = bbGt('evalRes',gt,dt,0.5,conf.eval_mul);
[fp,tp,score,miss] = bbGt('compRoc',gt,dt,1,conf.eval_ref);
miss=exp(mean(log(max(1e-10,1-miss)))); 
fprintf('miss rate:%.2f\n', miss*100);
% optionally plot roc
show = 0;
if(show)
figure(show); 
plotRoc([fp tp],'logx',1,'logy',1,'xLbl','fppi',...
'lims',[3.1e-3 1e1 .05 1],'color','g','smooth',1,'fpTarget',conf.eval_ref);
title(sprintf('log-average miss rate = %.2f%%',miss*100));
savefig([fullfile(cache_dir, conf.method_name) 'Roc'],show,'png');
end

% copy results to eval folder and run eval script to get figure.
folder1 = fullfile(cache_dir, conf.method_name);
folder2 = fullfile(pwd, 'external', 'code3.2.1', ['data-' conf.datasets], 'res', conf.method_name);
mkdir_if_missing(folder2);
copyfile(folder1, folder2);

diary off;
end