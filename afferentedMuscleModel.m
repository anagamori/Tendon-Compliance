%--------------------------------------------------------------------------
% afferentedMuscleModel.m
% Author: Akira Nagamori
% Last update: 5/18/2018
%--------------------------------------------------------------------------

function output = afferentedMuscleModel(t,Fs,Input,modelParameter,gainParameter,control_type)
%--------------------------------------------------------------------------
% model parameters
alpha = modelParameter.pennationAngle; % pennation angle
Lm_initial = modelParameter.muscleInitialLength; % muscle initial length
Lt_initial = modelParameter.tendonInitialLength; % tendon initial length
Lmt = Lm_initial*cos(alpha)+Lt_initial; % intial musculotendon length
L0 = modelParameter.optimalLength; % optimal muscle length
L_tendon = modelParameter.tendonSlackLength; % tendon slack length
L0T = L_tendon*1.05; % optimal tendon length

[Lce,Lse,Lmax] =  InitialLength(modelParameter); % Initial length of muscle and tendon

% F0: maximum force production capability
density = 1.06;
mass = modelParameter.mass; % muscle mass [kg]
PCSA = (mass*1000)/(density*L0); % PCSA of muscle
sigma = 31.8; % 31.8 specific tension
F0 = PCSA * sigma; % maximal force
offset = modelParameter.offset;
Fmax = modelParameter.Fmax-offset;

Ur = 0.8; % fractional activation level at which all motor units for a given muscle are recruited (0-1)
F_pcsa_slow = 0.5; % fractional PSCA of slow-twitch motor units (0-1)
U1_th = 0.01; % threshold for slow-twitch fiber
U2_th = Ur*F_pcsa_slow;

% activation-frequency relationship (Brown and Loeb 2000)
f_half = 8.5; % frequency at which the motor unit produces half of its maximal isometric force
fmin = 0.5*f_half; % minimum firing frequency of slow-twitch fiber
fmax = 2*f_half; % maximum firing frequency of slow-twitch fiber

f_half_fast = 34;% frequency at which the motor unit produces half of its maximal isometric force
fmin_fast = 0.5*f_half_fast; % minimum firing frequency of fast-twitch fiber
fmax_fast = 2*f_half_fast; % maximum firing frequency of fast-twitch fiber

% simulation parameters
% 'isometric' = Vce = 0

%--------------------------------------------------------------------------
% parameter initilization
U_eff = 0;
f_int_slow = 0;
f_eff_slow = 0;
f_eff_slow_dot = 0;
f_int_fast = 0;
f_eff_fast = 0;
f_eff_fast_dot = 0;

Af_slow = 0;
Af_fast = 0;

Y = 0;
S = 0;

Vce = 0; % muscle excursion velocity
Ace = 0;
%--------------------------------------------------------------------------
% storing variables
f_env_slow_vec = zeros(1,length(t));
f_int_slow_vec = zeros(1,length(t));
f_eff_slow_vec = zeros(1,length(t));
f_eff_slow_dot_vec = zeros(1,length(t));
f_env_fast_vec = zeros(1,length(t));
f_int_fast_vec = zeros(1,length(t));
f_eff_fast_vec = zeros(1,length(t));
f_eff_fast_dot_vec = zeros(1,length(t));

Af_slow_vec = zeros(1,length(t));
Af_fast_vec = zeros(1,length(t));

Y_vec = zeros(1,length(t));
S_vec = zeros(1,length(t));

Force = zeros(1,length(t));
Force_slow = zeros(1,length(t));
Force_fast = zeros(1,length(t));
ForceSE_vec = zeros(1,length(t));

OutputLse = zeros(1,length(t));
OutputLce = zeros(1,length(t));
OutputVce = zeros(1,length(t));
OutputAce = zeros(1,length(t));
Output_U_eff = zeros(1,length(t));
MuscleAcceleration = zeros(1,length(t));
MuscleVelocity = zeros(1,length(t));
MuscleLength = zeros(1,length(t));
MuscleLength(1) = Lce*L0/100;

%--------------------------------------------------------------------------
h = 1/Fs;

%--------------------------------------------------------------------------
% Muscle spindle related parameters
T_bag1 = 0;
T_dot_bag1 = 0;
T_bag2 = 0;
T_dot_bag2 = 0;
T_chain = 0;
T_dot_chain = 0;
f_dynamic = 0;
f_static = 0;

FR_Ia = zeros(1,length(t));
Input_Ia = zeros(1,length(t));
noise_Ia = zeros(1,length(t));
noise_Ia_filt = zeros(1,length(t));

%--------------------------------------------------------------------------
% GTO related parameters
s = tf('s');
H = (1.7*s^2+2.58*s+0.4)/(s^2+2.2*s+0.4);
Hd = c2d(H,h);
[num_GTO,den_GTO] = tfdata(Hd);
num_GTO = cell2mat(num_GTO);
den_GTO = cell2mat(den_GTO);

FR_Ib = zeros(1,length(t));
FR_Ib_temp = zeros(1,length(t));
x_GTO = zeros(1,length(t));
Input_Ib = zeros(1,length(t));
noise_Ib = zeros(1,length(t));
noise_Ib_filt = zeros(1,length(t));

%--------------------------------------------------------------------------
% Renshaw interneuron
delta = 0.0015;
tau1 = 0.14;
tau3 = 0.003;
tau4 = 0.09;
H_RI = (1+tau1*s)*exp(-delta*s)/((1+tau3*s)*(1+tau4*s));
Hd_RI = c2d(H_RI,1/Fs);
[num_RI,den_RI] = tfdata(Hd_RI);
num_RI = cell2mat(num_RI);
den_RI = cell2mat(den_RI);

FR_RI = zeros(1,length(t));
FR_RI_temp = zeros(1,length(t));
Input_RI = zeros(1,length(t));
noise_RI = zeros(1,length(t));
noise_RI_filt = zeros(1,length(t));

%--------------------------------------------------------------------------
% Propriospinal interneuron
FR_PN = zeros(1,length(t));
Input_PN = zeros(1,length(t));
noise_PN = zeros(1,length(t));
noise_PN_filt = zeros(1,length(t));

%--------------------------------------------------------------------------
% Neural drive related parameters
noise_ND = zeros(1,length(t));
noise_ND_filt = zeros(1,length(t));
ND_temp = 0;
ND = zeros(1,length(t));
ND_delayed = zeros(1,length(t));
%--------------------------------------------------------------------------
% noise related parameters
[b_noise,a_noise] = butter(4,100/(Fs/2),'low');
%--------------------------------------------------------------------------
% Gain parameters
K = gainParameter.K;
Ia_Gain = gainParameter.Ia_gain;
Ib_Gain = gainParameter.Ib_gain;
RI_Gain = gainParameter.RI_gain;
gamma_dynamic = gainParameter.gamma_dynamic;
gamma_static = gainParameter.gamma_static;
Ia_PC = gainParameter.Ia_PC;
Ib_PC = gainParameter.Ib_PC;
RI_PC = gainParameter.RI_PC;
PN_PC_Ia = gainParameter.PN_PC_Ia;
PN_PC_Ib = gainParameter.PN_PC_Ib;
PN_PC = gainParameter.PN_PC;
 
%--------------------------------------------------------------------------
distance_Muscle2SpinalCord = 0.8;
conductionVelocity_efferent = 48.5;
conductionVelocity_Ia = 64.5;
conductionVelocity_Ib = 59.0;
delay_synaptic = 2*Fs/1000;
delay_efferent = round(distance_Muscle2SpinalCord/conductionVelocity_efferent*1000)*Fs/1000 + delay_synaptic;
delay_Ia = round(distance_Muscle2SpinalCord/conductionVelocity_Ia*1000)*Fs/1000 + delay_synaptic;
delay_Ib = round(distance_Muscle2SpinalCord/conductionVelocity_Ib*1000)*Fs/1000 + 2*delay_synaptic;

delay_C = 50*Fs/1000;
%--------------------------------------------------------------------------
F_target = Fmax*Input;
Input_C_temp = 0;
noise_C = zeros(1,length(t));
noise_C_filt = zeros(1,length(t));
%--------------------------------------------------------------------------
% simulation
for i = 1:length(t)
    %----------------------------------------------------------------------
    % Muscle spindle output
    [AP_bag1,f_dynamic,T_bag1,T_dot_bag1] = bag1_model(f_dynamic,gamma_dynamic,T_bag1,T_dot_bag1,Lce,Vce,Ace,h);
    [AP_primary_bag2,AP_secondary_bag2,f_static,T_bag2,T_dot_bag2] = bag2_model(f_static,gamma_static,T_bag2,T_dot_bag2,Lce,Vce,Ace,h);
    [AP_primary_chain,AP_secondary_chain,T_chain,T_dot_chain] = chain_model(gamma_static,T_chain,T_dot_chain,Lce,Vce,Ace,h);
    [Output_Primary,~] = Spindle_Output(AP_bag1,AP_primary_bag2,AP_secondary_bag2,AP_primary_chain,AP_secondary_chain);
    FR_Ia(i) = Output_Primary;
    Input_Ia_temp = FR_Ia(i)/Ia_Gain + Ia_PC;
    if i > 5       
       [noise_Ia,noise_Ia_filt] = noise_Output(noise_Ia,noise_Ia_filt,abs(Input_Ia_temp),i,b_noise,a_noise);
        Input_Ia(i) = Input_Ia_temp + noise_Ia_filt(i);
        if Input_Ia(i) < 0
            Input_Ia(i) = 0;
        end
    end
    
    if i > 5
        [FR_Ib,FR_Ib_temp,x_GTO] = GTO_Output(FR_Ib,FR_Ib_temp,x_GTO,ForceSE,i,num_GTO,den_GTO);
        Input_Ib_temp = FR_Ib(i)/Ib_Gain + Ib_PC;
        [noise_Ib,noise_Ib_filt] = noise_Output(noise_Ib,noise_Ib_filt,abs(Input_Ib_temp),i,b_noise,a_noise);
        Input_Ib(i) = Input_Ib_temp + noise_Ib_filt(i);
        if Input_Ib(i) < 0
            Input_Ib(i) = 0;
        end
        
        [FR_RI,FR_RI_temp] = Renshaw_Output(FR_RI,FR_RI_temp,ND,i,num_RI,den_RI);
        Input_RI_temp = FR_RI(i)/RI_Gain + RI_PC;
        [noise_RI,noise_RI_filt] = noise_Output(noise_RI,noise_RI_filt,abs(Input_RI_temp),i,b_noise,a_noise);
        Input_RI(i) = Input_RI_temp + noise_RI_filt(i);
        if Input_RI(i) < 0
            Input_RI(i) = 0;
        end
    end
    if t > delay_Ib
        FR_PN(i) = (FR_Ia(i-delay_Ia)/Gain_Ia + PN_PC_Ia) + (FR_Ib(i-(delay_Ib-delay_synaptic))/Gain_Ib + PN_PC_Ib);
        Input_PN_temp = FR_PN(i) + PN_PC;
        [noise_PN,noise_PN_filt] = noise_Output(noise_PN,noise_PN_filt,abs(Input_PN_temp),i,b_noise,a_noise);
        Input_PN(i) = Input_PN_temp + noise_PN_filt(i);
        if Input_PN(i) < 0
            Input_PN(i) = 0;
        end
    end
    
    if i > delay_C
        Input_exc = Input_Ia(i-delay_Ia)+Input_PN(i-delay_synaptic);
        Input_inh = Input_Ib(i-delay_Ib)+Input_RI(i-delay_synaptic*2);
        if control_type == 0
            ND_temp = Input_exc - Input_inh + Input(i);
        elseif control_type == 1
            Input_C_temp = K*(F_target(i)-(ForceSE_vec(i-delay_C)-offset))/Fmax + Input_C_temp;
            [noise_C,noise_C_filt] = noise_Output(noise_C,noise_C_filt,abs(Input_C_temp),i,b_noise,a_noise);
            Input_C = Input_C_temp + noise_C_filt(i);
            ND_temp  = actionPotentialGeneration_function(Input_exc,Input_inh,2,2,Input_C);
            %ND_temp = Input_exc - Input_inh + Input_C;
        end
        if ND_temp < 0
            ND_temp = 0;
        end
        [noise_ND,noise_ND_filt] = noise_Output(noise_ND,noise_ND_filt,abs(ND_temp),i,b_noise,a_noise);
    end
    ND(i) = ND_temp + noise_ND_filt(i);
    if ND(i) < 0
        ND(i) = 0;
    end
    
    if i > delay_efferent
        ND_delayed(i) = ND(i-delay_efferent);
    end
    U = ND_delayed(i);
    
    if U >= U_eff
        T_U = 0.03;
    elseif U < U_eff
        T_U = 0.15;
    end
    
    U_eff_dot = (U - U_eff)/T_U;
    U_eff = U_eff_dot*1/Fs + U_eff;
    
    if U_eff < U1_th
        W1 = 0;
    elseif U_eff < U2_th
        W1 = (U_eff - U1_th)/(U_eff - U1_th);
    else
        W1 = (U_eff - U1_th)/((U_eff - U1_th) + (U_eff - U2_th));
    end
    if U_eff < U2_th
        W2 = 0;
    else
        W2 = (U_eff - U2_th)/((U_eff - U1_th) + (U_eff - U2_th));
    end
    
    % firing frequency input to second-order excitation dynamics of
    % slow-twitch fiber
    if U_eff >=  U1_th
        f_env_slow = (fmax-fmin)/(1-U1_th).*(U_eff-U1_th)+fmin;
        f_env_slow = f_env_slow/f_half;
    else
        f_env_slow = 0;
    end
    
    [f_int_slow,~] = f_slow_function(f_int_slow,f_env_slow,f_env_slow,f_eff_slow_dot,Af_slow,Lce,Fs);
    [f_eff_slow,f_eff_slow_dot] = f_slow_function(f_eff_slow,f_int_slow,f_env_slow,f_eff_slow_dot,Af_slow,Lce,Fs);
    
    if U_eff >= U2_th
        f_env_fast = (fmax_fast-fmin_fast)/(1-U2_th).*(U_eff-U2_th)+fmin_fast;
        f_env_fast = f_env_fast/f_half_fast;
    else
        f_env_fast = 0;
    end
    
    [f_int_fast,~] = f_fast_function(f_int_fast,f_env_fast,f_env_fast,f_eff_fast_dot,Af_fast,Lce,Fs);
    [f_eff_fast,f_eff_fast_dot] = f_fast_function(f_eff_fast,f_int_fast,f_env_fast,f_eff_fast_dot,Af_fast,Lce,Fs);
    
    Y = yield_function(Y,Vce,Fs);
    S = sag_function(S,f_eff_fast,Fs);
    Af_slow = Af_slow_function(f_eff_slow,Lce,Y);
    Af_fast = Af_fast_function(f_eff_fast,Lce,S);
    
    % activation dependent force of contractile elements   
    f_env_slow_vec(i) = f_env_slow;
    f_int_slow_vec(i) = f_int_slow;
    f_eff_slow_vec(i) = f_eff_slow;
    f_eff_slow_dot_vec(i) = f_eff_slow_dot;
    f_env_fast_vec(i) = f_env_fast;
    f_int_fast_vec(i) = f_int_fast;
    f_eff_fast_vec(i) = f_eff_fast;
    f_eff_fast_dot_vec(i) = f_eff_fast_dot;
    
    Af_slow_vec(i) = Af_slow;
    Af_fast_vec(i) = Af_fast;
    
    Y_vec(i) = Y;
    S_vec(i) = S;
    
    if Vce <= 0 % concentric
        FV1 = FV_con_slow_function(Lce,Vce);
        FV2 = FV_con_fast_function(Lce,Vce);
    elseif Vce > 0 % eccentric
        FV1 = FV_ecc_slow_function(Lce,Vce);
        FV2 = FV_ecc_fast_function(Lce,Vce);
    end
    FL1 = FL_slow_function(Lce);
    FL2 = FL_fast_function(Lce);
    FP1 = F_pe_1_function(Lce/Lmax,Vce);
    % passive element 2
    FP2 = F_pe_2_function(Lce);
    if FP2 > 0
        FP2 = 0;
    end
    
    Fce = U_eff*((W1*Af_slow*(FL1*FV1+FP2)) + (W2*Af_fast*(FL2*FV2+FP2)));
    if Fce < 0
        Fce = 0;
    elseif Fce > 1
        Fce = 1;
    end
    Fce = Fce + FP1;
    Force(i) = Fce*F0;
    Force_slow(i) = W1*Af_slow*F0;
    Force_fast(i) = W2*Af_fast*F0;
    
    ForceSE = F_se_function(Lse)*F0;
    ForceSE_vec(i) = ForceSE;
    k_0 = h*MuscleVelocity(i);
    l_0 = h*((ForceSE*cos(alpha) - Force(i)*(cos(alpha)).^2)/(mass) ...
        + (MuscleVelocity(i)).^2*tan(alpha).^2/(MuscleLength(i)));
    k_1 = h*(MuscleVelocity(i)+l_0/2);
    l_1 = h*((ForceSE*cos(alpha) - Force(i)*(cos(alpha)).^2)/(mass) ...
        + (MuscleVelocity(i)+l_0/2).^2*tan(alpha).^2/(MuscleLength(i)+k_0/2));
    k_2 = h*(MuscleVelocity(i)+l_1/2);
    l_2 = h*((ForceSE*cos(alpha) - Force(i)*(cos(alpha)).^2)/(mass) ...
        + (MuscleVelocity(i)+l_1/2).^2*tan(alpha).^2/(MuscleLength(i)+k_1/2));
    k_3 = h*(MuscleVelocity(i)+l_2);
    l_3 = h*((ForceSE*cos(alpha) - Force(i)*(cos(alpha)).^2)/(mass) ...
        + (MuscleVelocity(i)+l_2).^2*tan(alpha).^2/(MuscleLength(i)+k_2));
    MuscleLength(i+1) = MuscleLength(i) + 1/6*(k_0+2*k_1+2*k_2+k_3);
    MuscleVelocity(i+1) = MuscleVelocity(i) + 1/6*(l_0+2*l_1+2*l_2+l_3);
    % calculate muscle excursion acceleration based on the difference
    % between muscle force and tendon force
    MuscleAcceleration(i+1) = (ForceSE*cos(alpha) - Force(i)*(cos(alpha)).^2)/(mass) ...
        + (MuscleVelocity(i)).^2*tan(alpha).^2/(MuscleLength(i)+k_0/2);
    % integrate acceleration to get velocity
    % MuscleVelocity(i+1) = (MuscleAcceleration(i+1)+ ...
    %   MuscleAcceleration(i))/2*1/Fs+MuscleVelocity(i);
     % normalize each variable to optimal muscle length or tendon length
    Ace = MuscleAcceleration(i+1)/(L0/100);
    Vce = MuscleVelocity(i+1)/(L0/100);
    Lce = MuscleLength(i+1)/(L0/100);
    Lse = (Lmt - Lce*L0*cos(alpha))/L0T;
    
    OutputLse(i) = Lse; % normalized tendon length
    OutputLce(i) = Lce; % normalized muscle length
    OutputVce(i) = Vce; % normalized muscle excursion velocity
    OutputAce(i) = Ace; % normalized muscle excursion acceleration
   
    Output_U_eff(i) = U_eff;
end

output.F0 = F0;
output.Force_tendon = ForceSE_vec;
output.Force_total = Force;
output.Force_slow = Force_slow;
output.Force_fast = Force_fast;
output.Ia = FR_Ia;
output.Ib = FR_Ib;
output.RI = FR_RI;
output.PN = FR_PN;
output.Input_Ia = Input_Ia;
output.Input_Ib = Input_Ib;
output.Input_RI = Input_RI;
output.Input_PN = Input_PN;
output.ND = ND;
output.U_eff = Output_U_eff;
output.f_env_slow = f_env_slow_vec;
output.f_env_fast = f_env_fast_vec;
output.f_int_slow = f_int_slow_vec;
output.f_int_fast = f_int_fast_vec;
output.f_eff_slow = f_eff_slow_vec;
output.f_eff_fast = f_eff_fast_vec;
output.S = S_vec;
output.Y = Y_vec;
output.Af_slow = Af_slow_vec;
output.Af_fast = Af_fast_vec;
output.Lce = OutputLce;
output.Vce = OutputVce;
%--------------------------------------------------------------------------
% function used in simulation
    function Y = yield_function(Y,V,Fs)
        c_y = 0.35;
        V_y = 0.1;
        T_y = 0.2;
        
        Y_dot = (1-c_y*(1-exp(-abs(V)/V_y))-Y)/T_y;
        Y = Y_dot*1/Fs + Y;
    end

    function S = sag_function(S,f_eff,Fs)
        if f_eff < 0.1
            a_s = 1.76;
        else
            a_s = 0.96;
        end
        T_s = 0.043;
        S_dot = (a_s-S)/T_s;
        S = S_dot*1/Fs + S;
    end

    function Af = Af_slow_function(f_eff,L,Y)
        a_f = 0.56;
        n_f0 = 2.1;
        n_f1 = 5;
        n_f = n_f0 + n_f1*(1/L-1);
        Af = 1 - exp(-(Y*f_eff/(a_f*n_f))^n_f);
    end

    function Af = Af_fast_function(f_eff,L,S)
        a_f = 0.56;
        n_f0 = 2.1;
        n_f1 = 3.3;
        n_f = n_f0 + n_f1*(1/L-1);
        Af = 1 - exp(-((S*f_eff)/(a_f*n_f))^n_f);
    end

    function [f_out,f_out_dot,Tf] = f_slow_function(f_out,f_in,f_env,f_eff_dot,Af,Lce,Fs)
        %------------------------------------------------------------------
        % frequency-force relationship for slow-tiwtch fiber
        %------------------------------------------------------------------
        
        T_f1 = 0.0343;
        T_f2 = 0.0227;
        T_f3 = 0.047;
        T_f4 = 0.0252;
        
        if f_eff_dot >= 0
            Tf = T_f1*Lce^2+T_f2*f_env;
        else
            Tf = (T_f3 + T_f4*Af)/Lce;
        end
        f_out_dot = (f_in - f_out)/Tf;
        f_out = f_out_dot*1/Fs + f_out;
        
    end

    function [f_out,f_out_dot,Tf] = f_fast_function(f_out,f_in,f_env,f_eff_dot,Af,Lce,Fs)
        %------------------------------------------------------------------
        % frequency-force relationship for fast-tiwtch fiber
        %------------------------------------------------------------------
        
        T_f1 = 0.0206;
        T_f2 = 0.0136;
        T_f3 = 0.0282;
        T_f4 = 0.0151;
        
        if f_eff_dot >= 0
            Tf = T_f1*Lce^2+T_f2*f_env;
        else
            Tf = (T_f3 + T_f4*Af)/Lce;
        end
        f_out_dot = (f_in - f_out)/Tf;
        f_out = f_out_dot*1/Fs + f_out;
        
    end

    function FL = FL_slow_function(L)
        %------------------------------------------------------------------
        % force length (F-L) relationship for slow-tiwtch fiber
        % input: normalized muscle length and velocity
        % output: F-L factor (0-1)
        %------------------------------------------------------------------
        beta = 2.3;
        omega = 1.12;
        rho = 1.62;
        
        FL = exp(-abs((L^beta - 1)/omega)^rho);
    end

    function FL = FL_fast_function(L)
        %---------------------------
        % force length (F-L) relationship for fast-twitch fiber
        % input: normalized muscle length and velocity
        % output: F-L factor (0-1)
        %---------------------------
        beta = 1.55;
        omega = 0.75;
        rho = 2.12;
        
        FL = exp(-abs((L^beta - 1)/omega)^rho);
    end

    function FV = FV_con_slow_function(L,V)
        %---------------------------
        % concentric force velocity (F-V) relationship for slow-twitch fiber
        % input: normalized muscle length and velocity
        % output: F-V factor (0-1)
        %---------------------------
        Vmax = -7.88;
        cv0 = 5.88;
        cv1 = 0;
        
        
        FV = (Vmax - V)/(Vmax + (cv0 + cv1*L)*V);
    end

    function FV = FV_con_fast_function(L,V)
        %---------------------------
        % concentric force velocity (F-V) relationship for fast-twitch fiber
        % input: normalized muscle length and velocity
        % output: F-V factor (0-1)
        %---------------------------
        Vmax = -9.15;
        cv0 = -5.7;
        cv1 = 9.18;
        
        FV = (Vmax - V)/(Vmax + (cv0 + cv1*L)*V);
    end

    function FV = FV_ecc_slow_function(L,V)
        %---------------------------
        % eccentric force velocity (F-V) relationship for slow-twitch fiber
        % input: normalized muscle length and velocity
        % output: F-V factor (0-1)
        %---------------------------
        av0 = -4.7;
        av1 = 8.41;
        av2 = -5.34;
        bv = 0.35;
        FV = (bv - (av0 + av1*L + av2*L^2)*V)/(bv+V);
    end

    function FV = FV_ecc_fast_function(L,V)
        %---------------------------
        % eccentric force velocity (F-V) relationship for fast-twitch fiber
        % input: normalized muscle length and velocity
        % output: F-V factor (0-1)
        %---------------------------
        av0 = -1.53;
        av1 = 0;
        av2 = 0;
        bv = 0.69;
        FV = (bv - (av0 + av1*L + av2*L^2)*V)/(bv+V);
    end

    function Fpe1 = F_pe_1_function(L,V)
        %---------------------------
        % passive element 1
        % input: normalized muscle length
        % output: passive element force (0-1)
        %---------------------------
        c1_pe1 = 23;
        k1_pe1 = 0.046;
        Lr1_pe1 = 1.17;
        eta = 0.01;
        
        Fpe1 = c1_pe1 * k1_pe1 * log(exp((L - Lr1_pe1)/k1_pe1)+1) + eta*V;
        
    end

    function Fpe2 = F_pe_2_function(L)
        %---------------------------
        % passive element 2
        % input: normalized muscle length
        % output: passive element force (0-1)
        %---------------------------
        c2_pe2 = -0.02;
        k2_pe2 = -21;
        Lr2_pe2 = 0.70;
        
        Fpe2 = c2_pe2*exp((k2_pe2*(L-Lr2_pe2))-1);
        
    end

    function Fse = F_se_function(LT)
        %---------------------------
        % series elastic element (tendon)
        % input: tendon length
        % output: tendon force (0-1)
        %---------------------------
        cT_se = 27.8; %27.8
        kT_se = 0.0047;
        LrT_se = 0.964;
        
        Fse = cT_se * kT_se * log(exp((LT - LrT_se)/kT_se)+1);
        
    end


    function [Lce_initial,Lse_initial,Lmax] =  InitialLength(modelParameter)
        %---------------------------
        % Determine the initial lengths of muscle and tendon and maximal
        % muscle length
        %---------------------------
        
        % serires elastic element parameters
        cT = 27.8;
        kT = 0.0047;
        LrT = 0.964;
        % parallel passive element parameters
        c1 = 23;
        k1 = 0.046;
        Lr1 = 1.17;
        
        % passive force produced by parallel passive element at maximal
        % muscle length
        PassiveForce = c1 * k1 * log(exp((1 - Lr1)/k1)+1);
        % tendon length at the above passive force
        Normalized_SE_Length = kT*log(exp(PassiveForce/cT/kT)-1)+LrT;
        
        % maximal musculotendon length defined by joint range of motion
        Lmt_temp_max = modelParameter.optimalLength*cos(modelParameter.pennationAngle) ...
            +modelParameter.tendonSlackLength + 1;
        
        % optimal muscle length
        L0_temp = modelParameter.optimalLength;
        % optimal tendon length (Song et al. 2008)
        L0T_temp = modelParameter.tendonSlackLength*1.05;
        
        % tendon length at maximal muscle length
        SE_Length =  L0T_temp * Normalized_SE_Length;
        % maximal fasicle length
        FasclMax = (Lmt_temp_max - SE_Length)/L0_temp;
        % maximal muscle fiber length
        Lmax = FasclMax/cos(modelParameter.pennationAngle);
        
        % initial musculotendon length defined by the user input
        Lmt_temp = modelParameter.muscleInitialLength * cos(modelParameter.pennationAngle) + modelParameter.tendonInitialLength;
        
        % initial muscle length determined by passive muscle force and
        % tendon force
        InitialLength =  (Lmt_temp-(-L0T_temp*(kT/k1*Lr1-LrT-kT*log(c1/cT*k1/kT))))/(100*(1+kT/k1*L0T_temp/Lmax*1/L0_temp)*cos(modelParameter.pennationAngle));
        % normalize the muscle legnth to optimal muscle length
        Lce_initial = InitialLength/(L0_temp/100);
        % calculate initial length of tendon and normalize it to optimal
        % tendon length
        Lse_initial = (Lmt_temp - InitialLength*cos(modelParameter.pennationAngle)*100)/L0T_temp;
    end
    
    function [AP_bag1,f_dynamic,T,T_dot] = bag1_model(f_dynamic,gamma_dynamic,T,T_dot,L,V,A,step)
        p = 2;
        R = 0.46;
        a = 0.3;
        K_SR = 10.4649;
        K_PR = 0.15;
        M = 0.0002;
        LN_SR = 0.0423;
        L0_SR = 0.04; 
        L0_PR = 0.76;     
        tau_bag1 = 0.149;
        freq_bag1 = 60;
        
        beta0 = 0.0605;
        beta1 = 0.2592;
        Gamma1 = 0.0289;
        
        G = 20000;  
        
        if V >= 0
            C = 1;
        else
            C = 0.42;
        end
              
        df_dynamic = (gamma_dynamic^p/(gamma_dynamic^p+freq_bag1^p)-f_dynamic)/tau_bag1;
        f_dynamic = step*df_dynamic + f_dynamic;
        
        beta = beta0 + beta1 * f_dynamic;
        Gamma = Gamma1 * f_dynamic;
        
        T_ddot = K_SR/M * (C * beta * sign(V-T_dot/K_SR)*((abs(V-T_dot/K_SR))^a)*(L-L0_SR-T/K_SR-R)+K_PR*(L-L0_SR-T/K_SR-L0_PR)+M*A+Gamma-T);
        T_dot = T_ddot*step + T_dot;
        T = T_dot*step + T;
        
        AP_bag1 = G*(T/K_SR-(LN_SR-L0_SR));
    end

    function [AP_primary_bag2,AP_secondary_bag2,f_static,T,T_dot] = bag2_model(f_static,gamma_static,T,T_dot,L,V,A,step)
         p = 2;
        R = 0.46;
        a = 0.3;
        K_SR = 10.4649;
        K_PR = 0.15;
        M = 0.0002;        
        LN_SR = 0.0423;
        LN_PR = 0.89;
        L0_SR = 0.04; 
        L0_PR = 0.76;      
        L_secondary = 0.04;
        X = 0.7;
        tau_bag2 = 0.205;
        freq_bag2 = 60;
        
        beta0 = 0.0822;
        beta2 = -0.046;
        Gamma2 = 0.0636;
        
        if V >= 0
            C = 1; %constant describing the experimentally observed asymmetric effect of velocity on force production during lengthening and shortening
        else
            C = 0.42;
        end
        
        G = 10000; %7250 %3800
        
        df_static = (gamma_static^p/(gamma_static^p+freq_bag2^p)-f_static)/tau_bag2;
        f_static = step*df_static + f_static;
        
        beta = beta0 + beta2 * f_static;
        Gamma = Gamma2 * f_static;
        
        T_ddot = K_SR/M * (C * beta * sign(V-T_dot/K_SR)*((abs(V-T_dot/K_SR))^a)*(L-L0_SR-T/K_SR-R)+K_PR*(L-L0_SR-T/K_SR-L0_PR)+M*A+Gamma-T);
        T_dot = T_ddot*step + T_dot;
        T = T_dot*step + T;
        
        AP_primary_bag2 = G*(T/K_SR-(LN_SR-L0_SR));
        AP_secondary_bag2 = G*(X*L_secondary/L0_SR*(T/K_SR-(LN_SR-L0_SR))+(1-X)*L_secondary/L0_PR*(L-T/K_SR-L0_SR-LN_PR));
        
    end

    function [AP_primary_chain,AP_secondary_chain,T,T_dot] = chain_model(gamma_static,T,T_dot,L,V,A,step)
        p = 2;
        R = 0.46;
        a = 0.3;
        K_SR = 10.4649;
        K_PR = 0.15;
        M = 0.0002;        
        LN_SR = 0.0423;
        LN_PR = 0.89;
        L0_SR = 0.04; 
        L0_PR = 0.76;      
        L_secondary = 0.04;
        X = 0.7;
        freq_chain = 90;
        
        beta0 = 0.0822;
        beta2_chain = - 0.069;
        Gamma2_chain = 0.0954;
        
        
        if V >= 0
            C = 1; %constant describing the experimentally observed asymmetric effect of velocity on force production during lengthening and shortening
        else
            C = 0.42;
        end
        G = 10000; %7250    %3000
        
        f_static_chain = gamma_static^p/(gamma_static^p+freq_chain^p);
        
        beta = beta0 + beta2_chain * f_static_chain;
        Gamma = Gamma2_chain * f_static_chain;
        
        T_ddot = K_SR/M * (C * beta * sign(V-T_dot/K_SR)*((abs(V-T_dot/K_SR))^a)*(L-L0_SR-T/K_SR-R)+K_PR*(L-L0_SR-T/K_SR-L0_PR)+M*A+Gamma-T);
        T_dot = T_ddot*step + T_dot;
        T = T_dot*step + T;
        
        AP_primary_chain = G*(T/K_SR-(LN_SR-L0_SR));
        AP_secondary_chain = G*(X*L_secondary/L0_SR*(T/K_SR-(LN_SR-L0_SR))+(1-X)*L_secondary/L0_PR*(L-T/K_SR-L0_SR-LN_PR));        
    end

    function [Output_Primary,Output_Secondary] = Spindle_Output(AP_bag1,AP_primary_bag2,AP_secondary_bag2,AP_primary_chain,AP_secondary_chain)
        S_spindle = 0.156;
        
        if AP_bag1 < 0
            AP_bag1 = 0;
        end
        
        if AP_primary_bag2 < 0
            AP_primary_bag2 = 0;
        end
        
        if AP_primary_chain < 0
            AP_primary_chain = 0;
        end
        
        
        if AP_secondary_bag2 < 0
            AP_secondary_bag2 = 0;
        end
        
        if AP_secondary_chain < 0
            AP_secondary_chain = 0;
        end
        
        
        if AP_bag1 > (AP_primary_bag2+AP_primary_chain)
            Larger = AP_bag1;
            Smaller = AP_primary_bag2+AP_primary_chain;
        else
            Larger = AP_primary_bag2+AP_primary_chain;
            Smaller = AP_bag1;
        end
        Output_Primary = Larger + S_spindle * Smaller;
        Output_Secondary = AP_secondary_bag2 + AP_secondary_chain;
        
        if Output_Primary < 0
            Output_Primary = 0;
        elseif Output_Primary > 100000
            Output_Primary = 100000;
        end
        if Output_Secondary < 0
            Output_Secondary = 0;
        elseif Output_Secondary > 100000
            Output_Secondary = 100000;
        end
    end

    function [FR_Ib,FR_Ib_temp,x_GTO] = GTO_Output(FR_Ib,FR_Ib_temp,x_GTO,Force,index,num,den)
        G1 = 60;
        G2 = 4;
        x_GTO(index) = G1*log(Force/G2+1);
        FR_Ib_temp(index) = (num(3)*x_GTO(index-2) + num(2)*x_GTO(index-1) + num(1)*x_GTO(index) - den(3)*FR_Ib_temp(index-2) - den(2)*FR_Ib_temp(index-1))/den(1);
        FR_Ib(index) = FR_Ib_temp(index);
        if FR_Ib(index) < 0
            FR_Ib(index) = 0;
        end
    end

    function [FR_RI,FR_RI_temp] = Renshaw_Output(FR_RI,FR_RI_temp,ND,index,num,den)
        
        FR_RI_temp(index) = (num(3)*ND(index-2) + num(2)*ND(index-1) + num(1)*ND(index) - den(3)*FR_RI_temp(index-2) - den(2)*FR_RI_temp(index-1))/den(1);
        FR_RI(index) = FR_RI_temp(index);
        if FR_RI(index) < 0
            FR_RI(index) = 0;
        end
    end


    function [noise,noise_filt] = noise_Output(noise,noise_filt,Input,index,b,a)
        amp = 0.3;
        r = rand(1);
        noise(index) = 2*(r-0.5)*(sqrt(amp*Input)*sqrt(3));
        noise_filt(index) = (b(5)*noise(index-4) + b(4)*noise(index-3) + b(3)*noise(index-2) + b(2)*noise(index-1) + ...
            b(1)*noise(index) - a(5)*noise_filt(index-4) - a(4)*noise_filt(index-3) - a(3)*noise_filt(index-2) - ...
            a(2)*noise_filt(index-1))/a(1);      
        
    end

    function y = actionPotentialGeneration_function(Input_exc,Input_inh,n_exc,n_inh,IC)
        HYP = 2.0;
        OD = 2.0;        
        s_inh = - HYP/n_inh;
        s_exc = (1 + OD)/n_exc;
        y = s_exc*(Input_exc) + s_inh*(Input_inh) + IC;
    end
end
