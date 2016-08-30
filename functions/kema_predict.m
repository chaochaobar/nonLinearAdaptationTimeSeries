% function [A_u_l, A_v_l, A_uv_l, B_u_l, B_v_l, B_uv_l, AB_u_l, AB_v_l, AB_uv_l] = kema_predict(trainA_labeled, labelsA, trainA_unlabeled, unlabelsA, testA, tlabelsA, trainB_labeled, labelsB, trainB_unlabeled, unlabelsB, testB, tlabelsB, options)
%
% Inputs:
%	trainA_labeled:		Labeled Time Series (LTS) from Domain A
%	labelsA:			Corresponding Labels for Labeled Time Series from Domain A
%	trainA_unlabeled:	Unlabeled Time Series (UTS) from Domain A
%	unlabelsA:			Corresponding Labels for Unlabeled Time Series from Domain A
%	testA:				Time Series from Domain A for Validation
%	tlabelsA:			Corresponding Labels for Validation Time Series from Domain A
%	trainB_labeled:		Labeled Time Series from Domain B
%	labelsB:			Corresponding Labels for Time Series from Domain B
%	trainB_unlabeled:	Unlabeled Time Series from Domain B
%	unlabelsB:			Corresponding Labels for Unlabeled Time Series from Domain B
%	testB:				Time Series from Domain B for Validation
%	tlabelsB:			Corresponding Labels for Validation Time Series from Domain B
%	options:			Various options
%
% Outputs:
%	A_u_l:		Classification rate of UTS in Domain F using LTS -- Domain A
%	A_v_l:		Classification rate of VTS in Domain F using LTS -- Domain A
%	A_uv_l:		Classification rate of UTS+VTS in Domain F using LTS -- Domain A
%	B_u_l:		Classification rate of UTS in Domain F using LTS -- Domain B
%	B_v_l:		Classification rate of VTS in Domain F using LTS -- Domain B
%	B_uv_l:		Classification rate of UTS+VTS in Domain F using LTS -- Domain B
%	AB_u_l:		Classification rate of UTS in Domain F using LTS -- Domain A+B
%	AB_v_l:		Classification rate of VTS in Domain F using LTS -- Domain A+B
%	AB_uv_l:	Classification rate of UTS+VTS in Domain F using LTS -- Domain A+B
%
% Adeline Bailly - 2016
% adeline.bailly@univ-rennes2.fr

function [A_u_l, A_v_l, A_uv_l, B_u_l, B_v_l, B_uv_l, AB_u_l, AB_v_l, AB_uv_l] = kema_predict(trainA_labeled, labelsA, trainA_unlabeled, unlabelsA, testA, tlabelsA, trainB_labeled, labelsB, trainB_unlabeled, unlabelsB, testB, tlabelsB, options)

%% SSMA

n_cl = numel(unique(labelsA));

labelsAu = zeros(size(trainA_unlabeled, 2), 1); 
labelsBu = zeros(size(trainB_unlabeled, 2), 1); 

% construct graph
G1 = buildKNNGraph([trainA_labeled, trainA_unlabeled]', options.graph.nn, 1); 
G2 = buildKNNGraph([trainB_labeled, trainB_unlabeled]', options.graph.nn, 1); 

W = blkdiag(G1, G2); W = double(full(W)); 
clear G*

% similarity matrices
Y = [labelsA; labelsAu; labelsB; labelsBu]; 

Ws = repmat(Y, 1, length(Y)) == repmat(Y, 1, length(Y))'; 
Ws(Y == 0, :) = 0; Ws(:, Y == 0) = 0; Ws = double(Ws); 

Wd = repmat(Y, 1, length(Y)) ~= repmat(Y, 1, length(Y))'; 
Wd(Y == 0, :) = 0; Wd(:, Y == 0) = 0; Wd = double(Wd); 

Sw  = sum(sum(W)); 
Sws = sum(sum(Ws)); Ws = Ws/Sws*Sw; 
Swd = sum(sum(Wd)); Wd = Wd/Swd*Sw; 

clear Sw*

% dissimilarity matrices
D  = sum(W, 2); 
Ds = sum(Ws, 2); 
Dd = sum(Wd, 2); 

% graph laplacian matrix
L  = diag(D) - W; 
Ls = diag(Ds) - Ws; 
Ld = diag(Dd) - Wd; 

% 
% disp(L)
% disp(Ls)
mtxA = options.mu*L + Ls; mtxB = Ld; 

% RBF kernels
sigma1 = mean(pdist(trainA_labeled')); 
K1 = kernelmatrix('rbf', [trainA_labeled, trainA_unlabeled], [trainA_labeled, trainA_unlabeled], sigma1); 
sigma2 = mean(pdist(trainB_labeled')); 
K2 = kernelmatrix('rbf', [trainB_labeled, trainB_unlabeled], [trainB_labeled, trainB_unlabeled], sigma2); 

K = blkdiag(K1, K2); 

KT1 = kernelmatrix('rbf', [trainA_labeled, trainA_unlabeled], testA, sigma1); 

if (size(testB,1) > 0)
	KT2 = kernelmatrix('rbf', [trainB_labeled, trainB_unlabeled], testB, sigma2); 
end

[V, lambda] = gen_eig(K*mtxA*K, K*mtxB*K, 'LM'); 

[~, j] = sort(diag(lambda)); 
V = V(:, j); 

lenA = size(trainA_labeled, 2) + size(trainA_unlabeled, 2); 
% lenB = size(trainB_labeled, 2) + size(trainB_unlabeled, 2); 

%% rotation
E1 = V(1:lenA, :); 
E2 = V(lenA+1:end, :); 

sourceXpInv = (E1'*K1*-1)'; 
sourceXp = (E1'*K1)'; 
targetXp = (E2'*K2)'; 

sourceXpInv = zscore(sourceXpInv); 
sourceXp = zscore(sourceXp); 
targetXp = zscore(targetXp); 

ErrRec = zeros(numel(unique(labelsA)), size(V, 2)); 
ErrRecInv = zeros(numel(unique(labelsA)), size(V, 2)); 

m1 = zeros(numel(unique(labelsA)), size(V, 2)); 
m1inv = zeros(numel(unique(labelsA)), size(V, 2)); 
m2 = zeros(numel(unique(labelsA)), size(V, 2)); 

cls = unique(labelsA); 

for j = 1:size(V, 2)
	for i = 1:numel(cls)
		m1inv(i, j) = mean(sourceXpInv([labelsA; labelsAu]==cls(i), j)); 
		m1(i, j) = mean(sourceXp([labelsA; labelsAu]==cls(i), j)); 
		m2(i, j) = mean(targetXp([labelsB; labelsBu]==cls(i), j)); 

		ErrRec(i, j) = sqrt((mean(sourceXp([labelsA; labelsAu]==cls(i), j))-mean(targetXp([labelsB; labelsBu]==cls(i), j))).^2); 
		ErrRecInv(i, j) = sqrt((mean(sourceXpInv([labelsA; labelsAu]==cls(i), j))-mean(targetXp([labelsB; labelsBu]==cls(i), j))).^2); 
	end
end

mean(ErrRec); 
mean(ErrRecInv); 

Sc = max(ErrRec)>max(ErrRecInv); 
V(1:lenA, Sc) = V(1:lenA, Sc)*-1; 

clear cls E* i j
%% -- rotation

%clear L* W*

options.d = min(options.d, size(trainA_labeled, 2)+ size(trainB_labeled, 2)- n_cl); 
A_u_l  = zeros(options.d, 1);
A_v_l   = zeros(options.d, 1);
A_uv_l  = zeros(options.d, 1);
B_u_l   = zeros(options.d, 1);
B_v_l   = zeros(options.d, 1);
B_uv_l  = zeros(options.d, 1);
AB_u_l  = zeros(options.d, 1);
AB_v_l  = zeros(options.d, 1);
AB_uv_l = zeros(options.d, 1);

%fig = gcf;
set(gcf,'PaperUnits','centimeters');
set(gcf, 'PaperType','A4');
orient landscape;

%halfd = options.d / 2;

for dd = 1:options.d
	vAF = V(1:lenA, 1:dd); 
	vBF = V(lenA+1:end, 1:dd); 
	
	% Projection to latent space
	AtoF = vAF' * K1; 
	BtoF = vBF' * K2; 
	
	mA = mean(AtoF, 2)'; sA = std(AtoF, 0, 2)'; 
	mB = mean(BtoF, 2)'; sB = std(BtoF, 0, 2)'; 
	AtoF = ((AtoF' - repmat(mA, size(AtoF, 2), 1)) ./ repmat(sA, size(AtoF, 2), 1))'; 
	BtoF = ((BtoF' - repmat(mB, size(BtoF, 2), 1)) ./ repmat(sB, size(BtoF, 2), 1))'; 
	
% 	predictA = classify(AtoF', [BtoF(:, 1:size(labelsB, 1))]', [labelsB]); 
%	v = (labelsA == predictA(1:size(labelsA, 1))); 
%	AtoF_l_l(dd) = sum(v)/size(v, 1);
	
%	subplot(4,halfd,dd)
%	[cm, ll] = confusionmat(labelsA, predictA(1:size(labelsA, 1)));
%	imagesc(cm);
%	colormap(flipud(gray));
%	textStrings = num2str(cm(:), '%i');
%	textStrings = strtrim(cellstr(textStrings));
%	[x,y] = meshgrid(1:size(ll,1));
%	hStrings = text(x(:),y(:),textStrings(:),'HorizontalAlignment','center');
%	midValue = mean(get(gca,'CLim'));
%	textColors = repmat(cm(:) > midValue,1,3);

%	set(hStrings,{'Color'},num2cell(textColors,2));
%	set(gca,'XTick',1, 'XTickLabel',strcat('KEMA LTS - ', int2str(dd),'D'));
%	set(gca,'ytick',[],'yticklabel',[]);
	
	% Projection of xp data
	AxptoF = vAF' * KT1; 
	mA = mean(AxptoF, 2)'; sA = std(AxptoF, 0, 2)'; 
	AxptoF = ((AxptoF' - repmat(mA, size(AxptoF, 2), 1)) ./ repmat(sA, size(AxptoF, 2), 1))'; 
	
	if (size(testB,1) > 0)
		BxptoF = vBF' * KT2; 
		mB = mean(BxptoF, 2)'; sB = std(BxptoF, 0, 2)'; 
		BxptoF = ((BxptoF' - repmat(mB, size(BxptoF, 2), 1)) ./ repmat(sB, size(BxptoF, 2), 1))'; 
	end
	
	% Prediction
	AtstoF = AtoF(:, size(labelsA, 1)+1:end); 
	AtoF   = AtoF(:, 1:size(labelsA, 1));
	BtstoF = BtoF(:, size(labelsB, 1)+1:end); 
	BtoF   = BtoF(:, 1:size(labelsB, 1));
	
	obj = fitcdiscr(AtoF', labelsA);
	
 	predictA = predict(obj, AtstoF');
	A_u_l(dd) = sum((unlabelsA == predictA))/numel(predictA);
	
 	predictA = predict(obj, AxptoF');
	A_v_l(dd) = sum((tlabelsA == predictA))/numel(predictA);
	
 	predictA = predict(obj, [AtstoF'; AxptoF']);
	A_uv_l(dd) = sum(([unlabelsA; tlabelsA] == predictA))/numel(predictA);
	
	obj = fitcdiscr(BtoF', labelsB);
	
 	predictB = predict(obj, BtstoF');
	B_u_l(dd) = sum((unlabelsB == predictB))/numel(predictB);
	
	if (size(testB,1) > 0)
		predictB = predict(obj, BxptoF');
		B_v_l(dd) = sum((tlabelsB == predictB))/numel(predictB);
		predictB = predict(obj, [BtstoF'; BxptoF']);
		B_uv_l(dd) = sum(([unlabelsB; tlabelsB] == predictB))/numel(predictB);
	end
	
	obj = fitcdiscr([AtoF'; BtoF'], [labelsA; labelsB]);
	
 	predictAB = predict(obj, [AtstoF'; BtstoF']);
	AB_u_l(dd) = sum(([unlabelsA; unlabelsB] == predictAB))/numel(predictAB);
	
	if (size(testB,1) > 0)
		predictAB = predict(obj, [AxptoF'; BxptoF']);
		AB_v_l(dd) = sum(([tlabelsA; tlabelsB] == predictAB))/numel(predictAB);
		predictAB = predict(obj, [AtstoF'; BtstoF'; AxptoF'; BxptoF']);
		AB_uv_l(dd) = sum(([unlabelsA; unlabelsB; tlabelsA; tlabelsB] == predictAB))/numel(predictAB);
	end
	
% 	predictA = classify([AtoF'; AxptoF'], [BtoF, BxptoF]', [labelsB; unlabelsB; tlabelsB]);
%	v = ([labelsA; unlabelsA; tlabelsA] == predictA);
%	AtoF_all(dd) = sum(v)/size(v,1);
%	
%	subplot(4,halfd,options.d+dd)
%	[cm, ll] = confusionmat([labelsA; unlabelsA; tlabelsA], predictA);
%	imagesc(cm);
%	colormap(flipud(gray));
%	textStrings = num2str(cm(:), '%i');
%	textStrings = strtrim(cellstr(textStrings));
%	[x,y] = meshgrid(1:size(ll,1));
%	hStrings = text(x(:),y(:),textStrings(:),'HorizontalAlignment','center');
%	midValue = mean(get(gca,'CLim'));
%	textColors = repmat(cm(:) > midValue,1,3);
%	set(hStrings,{'Color'},num2cell(textColors,2));
%	set(gca,'XTick',1, 'XTickLabel',strcat('KEMA TS - ', int2str(dd),'D'));
%	set(gca,'ytick',[],'yticklabel',[]);
end
%saveas(fig, 'kema_cm', 'pdf');

if(options.fig == 1)
% 	xmin = min([min(AtoF(1,:)), min(AxptoF(1,:)), min(BtoF(1,:)), min(BxptoF(1,:))]);
% 	xmax = max([max(AtoF(1,:)), max(AxptoF(1,:)), max(BtoF(1,:)), max(BxptoF(1,:))]);
% 	ymin = min([min(AtoF(2,:)), min(AxptoF(2,:)), min(BtoF(2,:)), min(BxptoF(2,:))]);
% 	ymax = max([max(AtoF(2,:)), max(AxptoF(2,:)), max(BtoF(2,:)), max(BxptoF(2,:))]);
	t = num2cell([-4, 4, -4, 4]);
	[xmin, xmax, ymin, ymax] = deal(t{:});
	
	figur = gcf;
	set(gcf,'PaperUnits','centimeters');
	set(gcf, 'PaperType','A4');
	orient landscape;
	
	szpoint = 15;

	subplot(2, 3, 1);
	scatter(AtoF(1,:)', AtoF(2,:)', szpoint, labelsA,  'filled'), 
	colormap(jet(n_cl)),
	ylabel('dom. A to latent domain'),
	xlabel('labeled TS'),
	grid on,
	axis([xmin xmax ymin ymax]); 
	
% 	subplot(2, 3, 1);
% 	scatter3(AtoF(1, 1:size(labelsA, 1))', AtoF(2, 1:size(labelsA, 1))', AtoF(3, 1:size(labelsA, 1))', szpoint, labelsA,  'filled'), 
% 	colormap(jet(n_cl)),
% 	ylabel('dom. A to latent domain'),
% 	xlabel('labeled TS'),
% 	grid on,
% 	axis([xmin xmax ymin ymax ymin ymax]);
	
	subplot(2, 3, 2);
	scatter(AtstoF(1, :)', AtstoF(2, :)', szpoint, unlabelsA,  'filled'), 
	colormap(jet(n_cl)),
	xlabel('unlabeled TS'),
	grid on,
	axis([xmin xmax ymin ymax]); 
	
	subplot(2, 3, 3);
	scatter(AxptoF(1, :)', AxptoF(2, :)', szpoint, tlabelsA,  'filled'), 
	colormap(jet(n_cl)),
	xlabel('validation TS'),
	grid on,
	axis([xmin xmax ymin ymax]); 
	
	subplot(2, 3, 4);
	scatter(BtoF(1, :)', BtoF(2, :)', szpoint, labelsB,  'filled'), 
	colormap(jet(n_cl)),
	ylabel('dom. B to latent domain'),
	grid on,
	axis([xmin xmax ymin ymax]); 
	
	subplot(2, 3, 5);
	scatter(BtstoF(1, :)', BtstoF(2, :)', szpoint, unlabelsB,  'filled'), 
	colormap(jet(n_cl)),
	grid on,
	axis([xmin xmax ymin ymax]); 
	
	if (size(testB,1) > 0)
		subplot(2, 3, 6);
		scatter(BxptoF(1, :)', BxptoF(2, :)', 20, tlabelsB,  'filled'),
		colormap(jet(n_cl)),
		grid on,
		axis([xmin xmax ymin ymax]); 
	end
	
	saveas(figur, 'kema', 'pdf');
	clear figur;
	
	%disp('Press enter to continue'); pause
end

clear *toF D* K* L* Sc V W* Y ans d* fig l* m* options
clear predictA s* t* u* v*
