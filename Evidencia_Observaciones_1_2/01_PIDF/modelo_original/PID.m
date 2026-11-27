% Parámetros del cuarto de vehículo (Tabla VI)
M2 = 250; M1 = 50; K2 = 16000; B2 = 1500; K1 = 160000; B1 = 0;

% Espacio de estados
A_p = [0, 1, 0, 0;
    -K2/M2, -B2/M2, K2/M2, B2/M2;
     0, 0, 0, 1;
     K2/M1, B2/M1, -(K2+K1)/M1, -(B2+B1)/M1];
B_p = [0; 1/M2; 0; -1/M1];
C_p = [1 0 0 0]; % Salida: Desplazamiento z2
D_p= 0;

% Planta continua (Relación entre Fa y z2)
sys_susp = ss(A_p, B_p, C_p, D_p);

% Sintonización automática PID para respuesta rápida y estable
opts = pidtuneOptions('DesignFocus', 'disturbance-rejection');
[C_pid, info] = pidtune(sys_susp, 'PID', 15, opts); 
Kp = C_pid.Kp;
Ki = C_pid.Ki;
Kd = C_pid.Kd;

fprintf('Ganancias PID calculadas:\n Kp = %.4f\n Ki = %.4f\n Kd = %.4f\n', Kp, Ki, Kd);