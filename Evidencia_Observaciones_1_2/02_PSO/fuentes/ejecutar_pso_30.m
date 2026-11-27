function campana = ejecutar_pso_30(config, cola_progreso)
%EJECUTAR_PSO_30 Campana reproducible; guarda cada generacion y cada validacion.
% Helper de trabajador; iniciar desde INICIAR_PSO4 o PRUEBA_CORTA_PSO4.
% No ejecuta calibraciones automaticas ni modifica/guarda el modelo SLX.
if nargin < 1
    error('PSO4:Entrada','Use INICIAR_PSO4 o PRUEBA_CORTA_PSO4 desde la carpeta nueva.');
end
if nargin < 2, cola_progreso = []; end
if ~isfield(config,'realizar_preflight'), config.realizar_preflight = true; end
if ~isfield(config,'generar_resumen'), config.generar_resumen = true; end
if ~isfield(config,'evaluacion_rapida'), config.evaluacion_rapida = true; end
validar_config(config);
carpeta_codigo = fileparts(mfilename('fullpath'));
if ~isfile(config.archivo_referencia)
    error('PSO:Referencia', ...
        'Falta %s. Ejecute preparar_objetivo_normalizado antes de iniciar.',config.archivo_referencia);
end
datos = load(config.archivo_referencia,'referencia_objetivo');
if ~isfield(datos,'referencia_objetivo')
    error('PSO:Referencia','El archivo no contiene referencia_objetivo.');
end
referencia_objetivo = datos.referencia_objetivo;
requeridos = {'modelo','configuracion_modelo','parametros_fisicos','senal_activa','senal_pasiva'};
if ~all(isfield(referencia_objetivo,requeridos))
    error('PSO:Referencia','Actualice la calibracion con preparar_objetivo_normalizado.m.');
end
archivo_modelo = referencia_objetivo.configuracion_modelo.archivo;
if isempty(archivo_modelo) || ~isfile(archivo_modelo)
    error('PSO:Modelo','No se encuentra el SLX registrado en la calibracion.');
end
carpeta_anterior = pwd;
cd(fileparts(archivo_modelo));
restaurar_carpeta = onCleanup(@() cd(carpeta_anterior)); %#ok<NASGU>
addpath(carpeta_codigo,'-begin');
% Una copia antigua en la carpeta actual tiene prioridad sobre el path.
funciones = {'pso_una_ejecucion','evaluar_particula_normalizada', ...
    'funcion_objetivo_normalizada','configuracion_modelo_objetivo','analizar_resultados_pso'};
for k = 1:numel(funciones)
    esperado = fullfile(carpeta_codigo,[funciones{k} '.m']);
    if ~strcmpi(which(funciones{k}),esperado)
        error('PSO:CopiasAntiguas', ...
            'Actualice la copia de %s en la carpeta del modelo con la del paquete nuevo.',funciones{k});
    end
end
load_system(archivo_modelo);
modelo = referencia_objetivo.modelo;
if ~strcmpi(get_param(modelo,'FileName'),archivo_modelo)
    error('PSO:Modelo','Hay abierto otro modelo con el mismo nombre.');
end
if strcmp(get_param(modelo,'Dirty'),'on')
    error('PSO:ModeloSinGuardar', ...
        'Guarde su modelo corregido antes de iniciar una campana reproducible.');
end
if ~isequaln(configuracion_modelo_objetivo(modelo),referencia_objetivo.configuracion_modelo)
    error('PSO:Configuracion','La fuente/solver seleccionados no coinciden con la calibracion.');
end
if isfield(config,'usar_cache_exacta') && config.usar_cache_exacta
    comprobar_entrada_determinista(referencia_objetivo);
end

% Se conservan los bytes de las fuentes, no solo su nombre o fecha.
manifest = crear_manifest(modelo,config.archivo_referencia,carpeta_codigo);
carpeta_salida = config.carpeta_salida;
if ~isfolder(carpeta_salida), mkdir(carpeta_salida); end
archivo_campana = fullfile(carpeta_salida,'campana_pso.mat');
if isfile(archivo_campana)
    if ~config.reanudar
        error('PSO:ResultadosExistentes','Use reanudar=true o una carpeta_salida nueva.');
    end
    datos = load(archivo_campana,'campana'); campana = datos.campana;
    anterior = campana.config; actual = config;
    anterior.reanudar = true; actual.reanudar = true;
    if ~isequaln(anterior,actual) || ~isequaln(campana.manifest,manifest) || ...
            ~isequaln(campana.referencia_objetivo,referencia_objetivo)
        error('PSO:CampanaDistinta', ...
            'Cambio la configuracion o las fuentes. Para otro experimento use otra carpeta_salida.');
    end
else
    campana = struct('version',1,'config',config, ...
        'referencia_objetivo',referencia_objetivo,'manifest',{manifest}, ...
        'fecha_inicio',datestr(now,30),'release_matlab',version('-release'));
    campana.ejecuciones = cell(config.numero_ejecuciones,1);
    campana.estados_pso = cell(config.numero_ejecuciones,1);
    campana.eventos_error = {};
    for k = 1:config.numero_ejecuciones
        campana.ejecuciones{k} = struct('numero',k,'semilla',config.semillas(k), ...
            'estado','pendiente','error','');
    end
    carpeta_fuentes = fullfile(carpeta_salida,'fuentes');
    if ~isfolder(carpeta_fuentes), mkdir(carpeta_fuentes); end
    for k = 1:numel(manifest)
        [~,nombre,extension] = fileparts(manifest{k}.ruta);
        copyfile(manifest{k}.ruta,fullfile(carpeta_fuentes,sprintf('%02d_%s%s',k,nombre,extension)));
    end
    guardar_campana(archivo_campana,campana);
end
registrar(carpeta_salida,sprintf('Campana %d ejecuciones; origen del costo: %s.', ...
    config.numero_ejecuciones,config.origen_costo));

fast_anterior = get_param(modelo,'FastRestart');
restaurar_fast = onCleanup(@() restaurar_fast_restart(modelo,fast_anterior)); %#ok<NASGU>
if config.usar_fast_restart
    set_param(modelo,'FastRestart','on');
else
    set_param(modelo,'FastRestart','off');
end

% Preflight al iniciar o reanudar: no se cuenta como una repeticion PSO.
if config.realizar_preflight
ganancias_control = [0 0 0;10 10 4444];
campana.preflight = cell(2,1);
for k = 1:2
    [J, validacion, senales] = validar_particula(ganancias_control(k,:),referencia_objetivo,config);
    if k == 1
        error_senal = max(abs(senales.desplazamiento_activo-senales.desplazamiento_pasivo));
        tolerancia_senal = 1e-7+1e-5*max(abs(senales.desplazamiento_pasivo));
        if abs(J-1) > config.tolerancia_absoluta+config.tolerancia_relativa || error_senal > tolerancia_senal
            error('PSO:Preflight','Con C=0 deben coincidir activa/pasiva y obtenerse J cercano a 1.');
        end
    end
    campana.preflight{k} = validacion;
    registrar(carpeta_salida,sprintf('Comprobacion [%g %g %g]: J=%.12g; diferencia obj/trapz=%.4g.', ...
        ganancias_control(k,:),J,validacion.diferencia_costo));
end
guardar_campana(archivo_campana,campana);
end

for numero = 1:config.numero_ejecuciones
    if strcmp(campana.ejecuciones{numero}.estado,'completada'), continue; end
    if pausa_solicitada(config)
        registrar(carpeta_salida,'Pausa solicitada antes de iniciar otra busqueda.');
        return;
    end
    reloj_intento = tic;
    registro = campana.ejecuciones{numero};
    registro.estado = 'en_curso'; registro.error = '';
    campana.ejecuciones{numero} = registro;
    guardar_campana(archivo_campana,campana);
    registrar(carpeta_salida,sprintf('Ejecucion %d/%d; semilla %d.', ...
        numero,config.numero_ejecuciones,config.semillas(numero)));
    try
        resultado = pso_una_ejecucion(@costo_particula,config,config.semillas(numero), ...
            @guardar_generacion,campana.estados_pso{numero});
        reloj_validacion = tic;
        [J_validado,validacion,senales_validacion] = ...
            validar_particula(resultado.mejorABC,referencia_objetivo,config);
        tolerancia = config.tolerancia_absoluta + config.tolerancia_relativa*abs(resultado.mejorJ);
        if abs(J_validado-resultado.mejorJ) > tolerancia
            error('PSO:Validacion','El costo de la mejor particula no se reproduce.');
        end
        comprobar_fuentes(manifest);
        registro.mejorJ = resultado.mejorJ;
        registro.mejorABC = resultado.mejorABC;
        registro.historialJ = resultado.historialJ;
        registro.historialABC = resultado.historialABC;
        registro.evaluaciones = resultado.evaluaciones;
        if isfield(resultado,'simulaciones_reales')
            registro.simulaciones_reales = resultado.simulaciones_reales;
        end
        if isfield(resultado,'aciertos_cache')
            registro.aciertos_cache = resultado.aciertos_cache;
        end
        if isfield(resultado,'diagnosticos')
            registro.diagnosticos = resultado.diagnosticos;
            exportar_diagnosticos(resultado,carpeta_salida);
        end
        registro.simulaciones_validacion = 1;
        registro.tiempo_busqueda_segundos = resultado.tiempo_busqueda_segundos;
        registro.tiempo_validacion_segundos = toc(reloj_validacion);
        registro.tiempo_segundos = registro.tiempo_busqueda_segundos+registro.tiempo_validacion_segundos;
        registro.validacion = validacion;
        registro.diferencia_busqueda_validacion = abs(J_validado-resultado.mejorJ);
        registro.estado = 'completada'; registro.fecha_fin = datestr(now,30);
        archivo_ejecucion = fullfile(carpeta_salida,sprintf('ejecucion_%02d.mat',numero));
        save(archivo_ejecucion,'registro','senales_validacion','referencia_objetivo','config','-v7');
        campana.ejecuciones{numero} = registro;
        guardar_campana(archivo_campana,campana);
        registrar(carpeta_salida,sprintf('Final %d: J=%.12g; A=%.12g B=%.12g C=%.12g.', ...
            numero,registro.mejorJ,registro.mejorABC));
        % CSV parcial rapido; los graficos y el informe completo se generan al final.
        exportar_estado(campana,carpeta_salida);
    catch ME
        es_pausa = strcmp(ME.identifier,'PSO4:PausaSolicitada');
        es_interrupcion = es_pausa || contiene_interrupcion(ME);
        if es_interrupcion
            registro.estado = 'interrumpida';
        else
            registro.estado = 'fallida';
        end
        registro.error = getReport(ME,'extended','hyperlinks','off');
        campana.ejecuciones{numero} = registro;
        campana.eventos_error{end+1} = struct('ejecucion',numero, ...
            'fecha',datestr(now,30),'duracion_intento_segundos',toc(reloj_intento),'error',registro.error);
        guardar_campana(archivo_campana,campana);
        exportar_estado(campana,carpeta_salida);
        registrar(carpeta_salida,sprintf('%s en ejecucion %d: %s', ...
            upper(registro.estado),numero_global(config,numero),ME.message));
        if config.generar_resumen
            try
                analizar_resultados_pso(campana,fullfile(carpeta_salida,'resumen'));
            catch error_analisis
                warning('PSO:AnalisisParcial','No se genero el analisis parcial: %s',error_analisis.message);
            end
        end
        if es_pausa, return; end
        rethrow(ME); % No descarta fallos ni los sustituye por ejecuciones favorables.
    end
end
campana.fecha_fin = datestr(now,30);
guardar_campana(archivo_campana,campana);
if config.generar_resumen
    analizar_resultados_pso(campana,fullfile(carpeta_salida,'resumen'));
end
registrar(carpeta_salida,'Busqueda terminada; resultados y validacion guardados.');

    function J = costo_particula(abc)
        if config.evaluacion_rapida && strcmp(config.origen_costo,'simulink')
            opciones = struct('modo_evaluacion','rapida');
            J = evaluar_particula_normalizada(abc,referencia_objetivo,opciones);
            return;
        end
        [J_matlab,~,salida] = evaluar_particula_normalizada(abc,referencia_objetivo, ...
            struct('modo_evaluacion','completa'));
        J_obj = ultimo_obj(salida);
        comprobar_costos(J_matlab,J_obj,config);
        if strcmp(config.origen_costo,'simulink'), J = J_obj; else, J = J_matlab; end
    end

    function guardar_generacion(estado)
        comprobar_fuentes(manifest);
        if ~isequaln(configuracion_modelo_objetivo(modelo),referencia_objetivo.configuracion_modelo)
            error('PSO:Configuracion','Cambio el escenario o el solver durante la busqueda.');
        end
        campana.estados_pso{numero} = estado;
        guardar_campana(archivo_campana,campana);
        registrar(carpeta_salida,sprintf('Ejecucion %d; iteracion %d/%d; mejor J %.12g.', ...
            numero_global(config,numero),estado.iteracion,config.max_iteraciones,estado.mejorJ));
        exportar_diagnosticos(estado,carpeta_salida);
        if ~isempty(cola_progreso)
            evento = struct('numero_global',numero_global(config,numero), ...
                'iteracion',estado.iteracion,'max_iteraciones',config.max_iteraciones, ...
                'mejorJ',estado.mejorJ,'semilla',config.semillas(numero));
            if isfield(estado,'simulaciones_reales'), evento.simulaciones_reales = estado.simulaciones_reales; end
            if isfield(estado,'aciertos_cache'), evento.aciertos_cache = estado.aciertos_cache; end
            send(cola_progreso,evento);
        end
        if pausa_solicitada(config)
            error('PSO4:PausaSolicitada','Pausa solicitada: generacion completa guardada.');
        end
    end
end

function validar_config(c)
validateattributes(c.numero_ejecuciones,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.semillas,{'numeric'},{'vector','real','finite','integer', ...
    'numel',c.numero_ejecuciones,'>=',0,'<=',2^32-1});
assert(numel(unique(c.semillas))==c.numero_ejecuciones,'PSO:Semillas','Use semillas distintas.');
validateattributes(c.limite_inferior,{'numeric'},{'real','finite','numel',3,'nonnegative'});
validateattributes(c.limite_superior,{'numeric'},{'real','finite','numel',3,'nonnegative'});
assert(all(c.limite_superior(:)>=c.limite_inferior(:)), ...
    'PSO:Limites','Los limites superiores deben ser >= a los inferiores.');
validateattributes(c.n_particulas,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.max_iteraciones,{'numeric'},{'scalar','integer','positive'});
assert(c.limite_superior(3)<=5000,'PSO:Fuerza','El limite de C no debe superar 5000.');
assert(any(strcmp(c.origen_costo,{'simulink','matlab'})),'PSO:Costo','Origen de costo no valido.');
validateattributes(c.tolerancia_absoluta,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(c.tolerancia_relativa,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(c.realizar_preflight,{'logical'},{'scalar'});
validateattributes(c.generar_resumen,{'logical'},{'scalar'});
validateattributes(c.evaluacion_rapida,{'logical'},{'scalar'});
end

function [J,v,senales] = validar_particula(abc,ref,c)
[J_matlab,detalle,salida] = evaluar_particula_normalizada(abc,ref, ...
    struct('modo_evaluacion','completa'));
J_obj = ultimo_obj(salida); comprobar_costos(J_matlab,J_obj,c);
if strcmp(c.origen_costo,'simulink'), J=J_obj; else, J=J_matlab; end
activa = salida.get(ref.senal_activa); pasiva = salida.get(ref.senal_pasiva);
t = double(activa.Time(:)); z = double(activa.Data(:)); zp = double(pasiva.Data(:));
v = struct('J',J,'J_MATLAB',J_matlab,'ISE',detalle.ISE,'pico',detalle.pico, ...
    'RMS_desplazamiento',sqrt(detalle.ISE/(t(end)-t(1))), ...
    'reduccion_RMS_porcentaje',100*(1-sqrt(detalle.ISE/ref.ISE_pasiva)), ...
    'reduccion_pico_porcentaje',100*(1-detalle.pico/ref.pico_pasiva), ...
    'J_obj_simulink',J_obj,'diferencia_costo',abs(J_obj-J_matlab), ...
    'fuerza_RMS',NaN,'fuerza_pico',NaN,'esfuerzo_cuadratico',NaN);
senales = struct('tiempo',t,'desplazamiento_activo',z,'desplazamiento_pasivo',zp);
nombres = who(salida);
if any(strcmp(nombres,'force'))
    fuerza = salida.get('force');
    if isa(fuerza,'timeseries')
        tf = double(fuerza.Time(:)); f = double(fuerza.Data(:));
        if numel(tf)==numel(f) && numel(tf)>1 && all(diff(tf)>0) && ...
                isreal(f) && all(isfinite(f)) && all(isfinite(tf))
            v.esfuerzo_cuadratico = trapz(tf,f.^2);
            v.fuerza_RMS = sqrt(v.esfuerzo_cuadratico/(tf(end)-tf(1)));
            v.fuerza_pico = max(abs(f));
            senales.tiempo_fuerza = tf; senales.fuerza = f;
        end
    end
end
end

function J = ultimo_obj(salida)
obj = salida.get('obj');
if ~isa(obj,'timeseries') || isempty(obj.Data) || numel(obj.Data)~=numel(obj.Time)
    error('PSO:Obj','Configure obj como una Timeseries escalar en To Workspace.');
end
J = double(obj.Data(end));
if ~isscalar(J) || ~isreal(J) || ~isfinite(J) || J<0
    error('PSO:Obj','obj debe contener un costo escalar real, finito y no negativo.');
end
end

function comprobar_costos(a,b,c)
if abs(a-b) > c.tolerancia_absoluta+c.tolerancia_relativa*max(abs([a b]))
    error('PSO:Normalizacion', ...
        'obj=%.12g no coincide con J MATLAB=%.12g. Revise normalizadores y conexiones.',b,a);
end
end

function manifest = crear_manifest(modelo,archivo_ref,carpeta_codigo)
rutas = {get_param(modelo,'FileName'),archivo_ref};
bloques = find_system(modelo,'SearchDepth',1,'Type','Block');
encontro_fis = false;
for k = 1:numel(bloques)
    try
        expresion = strtrim(get_param(bloques{k},'FIS'));
    catch
        continue;
    end
    if numel(expresion)>=2 && ...
            ((expresion(1)==char(39) && expresion(end)==char(39)) || ...
             (expresion(1)==char(34) && expresion(end)==char(34)))
        expresion = expresion(2:end-1);
    end
    [~,~,ext] = fileparts(expresion);
    if ~strcmpi(ext,'.fis')
        error('PSO:FIS','Para archivar el FIS, use un archivo .fis en el bloque (como suspension.fis).');
    end
    rutas{end+1} = resolver_archivo(expresion); %#ok<AGROW>
    encontro_fis = true;
end
if ~encontro_fis, error('PSO:FIS','No se encontro el parametro FIS del controlador principal.'); end
archivo_parametros = which('parameters');
if isempty(archivo_parametros) || ...
        ~strcmpi(resolver_archivo(archivo_parametros),fullfile(carpeta_codigo,'parameters.m'))
    error('PSO4:Parametros','parameters.m debe resolverse desde esta carpeta PSO 4.');
end
rutas{end+1} = archivo_parametros;
codigo = dir(fullfile(carpeta_codigo,'*.m'));
[~,orden] = sort({codigo.name}); codigo = codigo(orden);
for k = 1:numel(codigo), rutas{end+1} = fullfile(carpeta_codigo,codigo(k).name); end
rutas = unique(rutas,'stable');
manifest = cell(numel(rutas),1);
for k = 1:numel(rutas)
    ruta = resolver_archivo(rutas{k});
    fid = fopen(ruta,'rb');
    if fid<0, error('PSO:Fuente','No se pudo leer %s.',ruta); end
    cierre = onCleanup(@() fclose(fid));
    contenido = fread(fid,Inf,'*uint8');
    manifest{k} = struct('ruta',ruta,'contenido',contenido);
    clear cierre;
end
end

function ruta = resolver_archivo(nombre)
if ~isfile(nombre), nombre_resuelto = which(nombre); else, nombre_resuelto = nombre; end
if isempty(nombre_resuelto), error('PSO:Fuente','No se encuentra %s.',nombre); end
[ok,atributos] = fileattrib(nombre_resuelto);
if ~ok, error('PSO:Fuente','No se puede resolver %s.',nombre_resuelto); end
ruta = atributos.Name;
end

function guardar_campana(archivo,campana)
temporal = [archivo '.tmp.mat'];
save(temporal,'campana','-v7');
[ok,mensaje] = movefile(temporal,archivo,'f');
if ~ok, error('PSO:Guardado','No se pudo guardar el checkpoint: %s',mensaje); end
end

function comprobar_fuentes(manifest)
for k = 1:numel(manifest)
    fid = fopen(manifest{k}.ruta,'rb');
    if fid<0, error('PSO:FuenteCambio','No se puede leer %s.',manifest{k}.ruta); end
    cierre = onCleanup(@() fclose(fid));
    actual = fread(fid,Inf,'*uint8');
    clear cierre;
    if ~isequal(actual,manifest{k}.contenido)
        error('PSO:FuenteCambio', ...
            'Cambio una fuente durante la campana: %s. No mezcle configuraciones.',manifest{k}.ruta);
    end
end
end

function exportar_estado(campana,carpeta)
N = campana.config.numero_ejecuciones;
estado = cell(N,1); error_texto = cell(N,1); J=nan(N,1); abc=nan(N,3);
for k = 1:N
    r=campana.ejecuciones{k}; estado{k}=r.estado; error_texto{k}=r.error;
    if strcmp(r.estado,'completada'), J(k)=r.mejorJ; abc(k,:)=r.mejorABC; end
end
tabla = table((1:N)',campana.config.semillas(:),estado,J,abc(:,1),abc(:,2),abc(:,3),error_texto, ...
    'VariableNames',{'Ejecucion','Semilla','Estado','CostoFinal','A','B','C','Error'});
writetable(tabla,fullfile(carpeta,'avance_ejecuciones.csv'));
end

function registrar(carpeta,mensaje)
linea = sprintf('[%s] %s\n',datestr(now,'yyyy-mm-dd HH:MM:SS'),mensaje);
fprintf('%s',linea);
fid = fopen(fullfile(carpeta,'registro_pso.txt'),'a','n','UTF-8');
if fid<0, error('PSO:Registro','No se pudo abrir registro_pso.txt.'); end
cierre = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',linea);
end

function restaurar_fast_restart(modelo,valor)
if bdIsLoaded(modelo), set_param(modelo,'FastRestart',valor); end
end

function numero = numero_global(config,local)
numero = local;
if isfield(config,'numero_global'), numero = config.numero_global; end
end

function tf = pausa_solicitada(config)
tf = isfield(config,'archivo_pausa') && isfile(config.archivo_pausa);
end

function tf = contiene_interrupcion(ME)
mensaje = lower(ME.message);
tf = contains(mensaje,'interrupt.') || ...
    contains(mensaje,'program interruption') || ...
    contains(mensaje,'operation terminated by user');
for k = 1:numel(ME.cause)
    tf = tf || contiene_interrupcion(ME.cause{k});
end
end

function exportar_diagnosticos(estado,carpeta)
if ~isfield(estado,'diagnosticos') || isempty(estado.diagnosticos), return; end
d = estado.diagnosticos;
if istable(d)
    tabla = d;
elseif isstruct(d) && isscalar(d) && isfield(d,'diversidad_normalizada')
    filas = 1:estado.iteracion+1;
    valores = [d.iteracion(filas,:),d.diversidad_normalizada(filas,:), ...
        d.fraccion_limite_inferior(filas,:),d.fraccion_limite_superior(filas,:), ...
        d.posiciones_unicas(filas,:),d.solicitudes_costo(filas,:), ...
        d.simulaciones_reales(filas,:),d.aciertos_cache(filas,:)];
    nombres = {'Iteracion','DiversidadA','DiversidadB','DiversidadC', ...
        'FraccionLimiteInferiorA','FraccionLimiteInferiorB','FraccionLimiteInferiorC', ...
        'FraccionLimiteSuperiorA','FraccionLimiteSuperiorB','FraccionLimiteSuperiorC', ...
        'PosicionesUnicas','SolicitudesCosto','SimulacionesReales','AciertosCache'};
    tabla = array2table(valores,'VariableNames',nombres);
else
    return;
end
writetable(tabla,fullfile(carpeta,'diagnosticos_enjambre.csv'));
end

function comprobar_entrada_determinista(ref)
% El cache solo se habilita para el pulso fijo verificado en este paquete.
fuentes = ref.configuracion_modelo.fuentes;
pulso = false; interruptor = false;
for k = 1:numel(fuentes)
    f = fuentes{k};
    if strcmp(f.tipo,'DiscretePulseGenerator'), pulso = true; end
    if strcmp(f.tipo,'ManualSwitch')
        interruptor = isfield(f,'sw') && strcmp(strtrim(f.sw),'1');
    end
end
if ~pulso || ~interruptor
    error('PSO4:CacheEntrada', ...
        'El cache exacto requiere el pulso determinista seleccionado. Desactive usar_cache_exacta para otro escenario.');
end
end
