function config=preparar_reproduccion_pso(origen,destino)
% Crea una copia portable de las fuentes; NO inicia las 30 busquedas.
% Conserva denominadores, semillas, modelo y algoritmo. Solo reubica rutas.
% Despues: campana=ejecutar_pso4(config); (puede tardar muchas horas).
if nargin<1,origen=fullfile(fileparts(mfilename('fullpath')),'02_PSO','fuentes');end
if nargin<2,destino=fullfile(fileparts(mfilename('fullpath')),['reproduccion_' datestr(now,'yyyymmdd_HHMMSS')]);end
assert(~isfolder(destino),'Use una carpeta NUEVA para no sobreescribir resultados.');
if bdIsLoaded('ActiveSuspensionv2')
 error('Cierre primero el modelo ActiveSuspensionv2 para no mezclar copias. No se cierra ni modifica automaticamente.');
end
mkdir(destino);copyfile(fullfile(origen,'*'),destino);
old=pwd;cd(destino);cleanup=onCleanup(@() cd(old));addpath(destino,'-begin');
load_system(fullfile(destino,'ActiveSuspensionv2.slx'));
cfgActual=configuracion_modelo_objetivo('ActiveSuspensionv2');
for n={'referencia_calibrada_origen.mat','referencia_objetivo_normalizado.mat'}
 p=fullfile(destino,n{1});D=load(p,'referencia_objetivo');referencia_objetivo=D.referencia_objetivo;
 antes=referencia_objetivo.configuracion_modelo;antes.archivo=cfgActual.archivo;
 assert(isequaln(orderfields(antes),orderfields(cfgActual)), ...
  'La configuracion del modelo no coincide; no se recalibran ni alteran los resultados.');
 referencia_objetivo.configuracion_modelo=cfgActual;save(p,'referencia_objetivo','-v7');
end
config=configuracion_pso4;config.carpeta_proyecto=destino;
config.archivo_referencia=fullfile(destino,'referencia_objetivo_normalizado.mat');
config.carpeta_salida=fullfile(destino,'resultados_nuevos');config.reanudar=false;
preparar_pso4(config);
save(fullfile(destino,'config_reproduccion.mat'),'config');
fprintf('Copia preparada. No se ha ejecutado ninguna busqueda.\n');
fprintf('Para ejecutar: campana=ejecutar_pso4(config);\n');
end
