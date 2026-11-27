function registro = trabajador_pso4(numero, config, cola_progreso)
% Un proceso ejecuta una busqueda completa. Nunca escribe el resumen conjunto.
carpeta = config.carpeta_proyecto;
anterior = pwd; ruta_anterior = path;
restaurar_entorno = onCleanup(@() restaurar_rutas(anterior,ruta_anterior)); %#ok<NASGU>
cd(carpeta); addpath(carpeta,'-begin');
hilos_anteriores = maxNumCompThreads(config.hilos_por_trabajador);
restaurar_hilos = onCleanup(@() maxNumCompThreads(hilos_anteriores)); %#ok<NASGU>
% Aislar cache por tarea evita colisiones de compilacion entre procesos.
tarea = getCurrentTask;
if isempty(tarea), identificador=0; else, identificador=tarea.ID; end
cache = fullfile(config.carpeta_salida,'cache_workers',sprintf('proceso_%d',identificador));
anterior_gen = Simulink.fileGenControl('getConfig');
cache_anterior = anterior_gen.CacheFolder;
codigo_anterior = anterior_gen.CodeGenFolder;
restaurar_gen = onCleanup(@() restaurar_cache(cache_anterior,codigo_anterior)); %#ok<NASGU>
Simulink.fileGenControl('set','CacheFolder',fullfile(cache,'cache'), ...
    'CodeGenFolder',fullfile(cache,'codigo'),'createDir',true);
modelo = 'ActiveSuspensionv2';
archivo_modelo = fullfile(carpeta,[modelo '.slx']);
if bdIsLoaded(modelo) && ~strcmpi(get_param(modelo,'FileName'),archivo_modelo)
    if strcmp(get_param(modelo,'Dirty'),'on')
        error('PSO4:ModeloWorker','El trabajador tiene otro modelo con cambios sin guardar.');
    end
    close_system(modelo,0);
end
evalin('base','parameters;');
local = config;
local.numero_global = numero;
local.carpeta_campana = config.carpeta_salida;
local.archivo_pausa = fullfile(config.carpeta_salida,'PAUSAR.txt');
local.numero_ejecuciones = 1;
local.semillas = config.semillas(numero);
local.carpeta_salida = fullfile(config.carpeta_salida,'ejecuciones',sprintf('ejecucion_%02d',numero));
local.realizar_preflight = false;
local.generar_resumen = false;
if ~isfolder(local.carpeta_salida), mkdir(local.carpeta_salida); end
bloqueo_ejecucion = bloquear_pso4(fullfile(local.carpeta_salida,'ESCRITOR.lock')); %#ok<NASGU>
campana_local = ejecutar_pso_30(local,cola_progreso);
registro = campana_local.ejecuciones{1};
registro.numero = numero;
registro.ruta_checkpoint = fullfile(local.carpeta_salida,'campana_pso.mat');
end

function restaurar_rutas(carpeta,ruta)
cd(carpeta); path(ruta);
end

function restaurar_cache(cache,codigo)
try
    Simulink.fileGenControl('set','CacheFolder',cache,'CodeGenFolder',codigo,'createDir',true);
catch
    % No ocultar el error/interrupcion original por un fallo de limpieza.
end
end
