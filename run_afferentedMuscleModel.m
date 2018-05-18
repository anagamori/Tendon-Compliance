close all
clear all
clc

codeFolder = '/Users/akira/Documents/Github/Tendon-Compliance';
dataFolder = '/Volumes/DATA2/TwoMuscleSystemData/CombinedModel/ModelTesting';

modelParameter.pennationAngle = 3.1*pi/180; %9.6
modelParameter.optimalLength = 5.1; % 6.8
modelParameter.tendonSlackLength = 27.1; % 24.1
modelParameter.mass = 0.02;
modelParameter.muscleInitialLength = 5.1; % muscle initial length
modelParameter.tendonInitialLength = 27.1;

Fs = 10000;
t = 0:1/Fs:5;

amp = 0.2;
input = [zeros(1,1*Fs) amp*[0:1/Fs:1] amp*ones(1,length(t)-1*Fs-length(amp*[0:1/Fs:1]))];

output = afferentedMuscleModel(t,Fs,input,modelParameter);

figure(1)
plot(t,output.Force_tendon)