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

control_type = 1;

gainParameter.Ia_gain = 400;
gainParameter.Ib_gain = 400;
gainParameter.RI_gain = 2;
gainParameter.gamma_dynamic = 50;
gainParameter.gamma_static = 50;
gainParameter.Ia_PC = -1;
gainParameter.Ib_PC = -1;
gainParameter.RI_PC = -1;
gainParameter.PN_PC_Ia = -1;
gainParameter.PN_PC_Ib = -1;
gainParameter.PN_PC = -1;
gainParameter.K = 0.0003;
 
Fs = 10000;
t = 0:1/Fs:5;

amp = 0.1;
input = [zeros(1,1*Fs) amp*[0:1/Fs:1] amp*ones(1,length(t)-1*Fs-length(amp*[0:1/Fs:1]))];

output = afferentedMuscleModel(t,Fs,input,modelParameter,gainParameter,control_type);

figure(1)
plot(t,input*output.F0)
hold on
plot(t,output.Force_tendon)