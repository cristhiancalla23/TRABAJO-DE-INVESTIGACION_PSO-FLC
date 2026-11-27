function verificar_archivos_pso4
% Solo lecturas; no abre Simulink ni crea pools de trabajadores.
carpeta=fileparts(mfilename('fullpath'));
funciones={'configuracion_pso4','ejecutar_pso4','trabajador_pso4','ejecutar_pso_30', ...
    'pso_una_ejecucion','evaluar_particula_normalizada','funcion_objetivo_normalizada', ...
    'configuracion_modelo_objetivo','analizar_resultados_pso','guardar_pso4', ...
    'manifest_pso4','bloquear_pso4','probar_bloqueo_pso4','preparar_pso4','verificar_modelo_pso4'};
for k=1:numel(funciones)
    assert(strcmpi(which(funciones{k}),fullfile(carpeta,[funciones{k} '.m'])), ...
        'PSO4:Ruta','%s se resuelve fuera de esta carpeta. Use cd y addpath de PSO 4.',funciones{k});
end
datos=load(fullfile(carpeta,'referencia_calibrada_origen.mat'),'referencia_objetivo');
r=datos.referencia_objetivo;
assert(r.alpha==0.5 && r.ISE_pasiva>0 && r.pico_pasiva>0);
assert(isfile(fullfile(carpeta,'ActiveSuspensionv2.slx')) && ...
    isfile(fullfile(carpeta,'suspension.fis')) && isfile(fullfile(carpeta,'parameters.m')));
c=configuracion_pso4;
assert(c.numero_trabajadores==4 && c.hilos_por_trabajador==1);
assert(c.numero_ejecuciones==30 && numel(unique(c.semillas))==30);
fprintf('Archivos y rutas de PSO 4 correctos; referencia alpha=%.2f.\n',r.alpha);
end
