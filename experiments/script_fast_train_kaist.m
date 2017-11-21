function script_fast_train_kaist()
% script_faster_rcnn_VGG16_kaist()
% Faster rcnn training and testing with VGG16 model
% --------------------------------------------------------
% Faster R-CNN
% Copyright (c) 2017, Zhewei Xu
% Licensed under The MIT License [see LICENSE for details]
% --------------------------------------------------------

clc;
clear mex;
clear is_valid_handle; % to clear init_key
run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'startup'));
%% -------------------- CONFIG --------------------
opts.caffe_version          = 'caffe_faster_rcnn';
% opts.gpu_id                 = auto_select_gpu;
opts.gpu_id                 = 3;
active_caffe_mex(opts.gpu_id, opts.caffe_version);

exp_name = 'KAIST';
% do validation, or not 
opts.do_val                 = true; 
% model
model                       = Model.VGG16_for_Fast_RCNN('Fast');
% cache base
cache_base_proposal         = 'vgg16_anchor';
cache_base_fast_rcnn        = 'vgg16_conv53_hole_miniscale';
% train/test data
dataset                     = [];
use_flipped                 = false;
dataset                     = Dataset.kaist_lwir_trainval(dataset, 'train-all-lwir-03', use_flipped);
dataset                     = Dataset.kaist_lwir_test(dataset, 'test-all-lwir-20', use_flipped);

%% -------------------- TRAIN --------------------
% conf
conf_proposal               = proposal_config(model);
conf_fast_rcnn              = fast_rcnn_config(model);
% set cache folder for each stage
model                       = Faster_RCNN_Train.set_cache_folder_fast(cache_base_proposal, cache_base_fast_rcnn, model);
% generate anchors and pre-calculate output size of rpn network 
conf_proposal.exp_name = exp_name;
[conf_proposal.anchors, conf_proposal.output_width_map, conf_proposal.output_height_map] ...
                            = proposal_prepare_anchors(conf_proposal, model.stage1_rpn.cache_name, model.stage1_rpn.test_net_def_file);
%%  stage one proposal
fprintf('\n***************\nstage one proposal \n***************\n');
% train
model.stage1_rpn            = Faster_RCNN_Train.do_proposal_train_pd(conf_proposal, dataset, model.stage1_rpn, opts.do_val);
% proposal
dataset.roidb_train         = cellfun(@(x, y) Faster_RCNN_Train.do_generate_proposal_pd(conf_proposal, model.stage1_rpn, x, y), dataset.imdb_train, dataset.roidb_train, 'UniformOutput', false);
dataset.roidb_test          = Faster_RCNN_Train.do_generate_proposal_pd(conf_proposal, model.stage1_rpn, dataset.imdb_test, dataset.roidb_test);
% test
conf_proposal.method_name  = 'RPN-anchor';
model.stage1_rpn.nms        = model.nms.test;
Faster_RCNN_Train.do_proposal_test_pd(conf_proposal, model.stage1_rpn, dataset.imdb_test, dataset.roidb_test);

%%  stage one fast rcnn
fprintf('\n***************\nstage one fast rcnn\n***************\n');
% train
conf_fast_rcnn.exp_name     = exp_name;
model.stage1_fast_rcnn      = Faster_RCNN_Train.do_fast_rcnn_train_pd(conf_fast_rcnn, dataset, model.stage1_fast_rcnn, opts.do_val);
% test_proposal
model.stage1_rpn.nms        = model.nms.test;
dataset.roidb_test          = Faster_RCNN_Train.do_generate_proposal_pd(conf_proposal, model.stage1_rpn, dataset.imdb_test, dataset.roidb_test);
% test
conf_fast_rcnn.method_name  = 'fast-conv53-hole-miniscale';
[~,opts.stage1_fast_miss]   = Faster_RCNN_Train.do_fast_rcnn_test_pd(conf_fast_rcnn, model.stage1_fast_rcnn, dataset.imdb_test, dataset.roidb_test);

end

function [anchors, output_width_map, output_height_map] = proposal_prepare_anchors(conf, cache_name, test_net_def_file)
    [output_width_map, output_height_map] ...                           
                                = proposal_calc_output_size_pd(conf, test_net_def_file);
    anchors                = proposal_generate_anchors_pd(cache_name, ...
                                    'scales', [45 52 57 63 71 80 92 109 140]./16.*sqrt(0.41), ...%2.^[3:5],...
                                    'ratios', [1 / 0.41], ...%[0.5, 1, 2],...
                                    'exp_name', conf.exp_name);
end

function conf = proposal_config(model)
    conf = proposal_config_pd('image_means', model.mean_image,...
                              'feat_stride', model.feat_stride ...
                             ,'scales',        512  ...
                             ,'max_size',      640  ...
                             ,'ims_per_batch', 1    ...
                             ,'batch_size',    120  ...
                             ,'fg_fraction',   1/6  ...
                             ,'bg_weight',     1.0  ...
                             ,'fg_thresh',     0.5  ...
                             ,'bg_thresh_hi',  0.5  ...
                             ,'bg_thresh_lo',  0    ...
                             ,'test_scales',   512  ...
                             ,'test_max_size', 640  ...
                             ,'test_nms',      0.5  ...
                             ,'test_min_box_height',50 ...
                             ,'datasets',     'kaist' ...
                              );
    % for eval_pLoad
    pLoad = {'lbls',{'person'},'ilbls',{'people','person?','cyclist'},'squarify',{3,.41}};
    pLoad = [pLoad 'hRng',[55 inf], 'vType',{{'none','partial'}},'xRng',[5 635],'yRng',[5 475]];
    conf.eval_pLoad = pLoad;
end

function conf = fast_rcnn_config(model)
    conf = fast_rcnn_config_pd('image_means',   model.mean_image ...
                              ,'scales',        512  ...
                              ,'max_size',      640  ...
                              ,'ims_per_batch', 2    ...
                              ,'batch_size',    128  ...
                              ,'fg_fraction',   0.25 ...
                              ,'fg_thresh',     0.5  ...
                              ,'bg_thresh_hi',  0.5  ...
                              ,'bg_thresh_lo',  0    ...
                              ,'bbox_thresh',   0.5  ...
                              ,'test_scales',   512  ...
                              ,'test_max_size', 640  ...
                              ,'test_nms',      0.5  ...
                              ,'datasets',     'kaist' ...
                               );
    % for eval_pLoad
    pLoad = {'lbls',{'person'},'ilbls',{'people','person?','cyclist'},'squarify',{3,.41}};
    pLoad = [pLoad 'hRng',[55 inf], 'vType',{{'none','partial'}},'xRng',[5 635],'yRng',[5 475]];
    conf.eval_pLoad = pLoad;
end