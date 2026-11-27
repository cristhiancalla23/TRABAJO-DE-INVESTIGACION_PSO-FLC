function campana = ejecutar_pso4(config)
% Coordinador: cuatro procesos, checkpoints separados, un solo escritor agregado.
if nargin < 1, config = configuracion_pso4; end
validar(config);
carpeta = fileparts(mfilename('fullpath'));
assert(strcmpi(config.carpeta_proyecto,carpeta),'PSO4:Ruta', ...
    'La configuracion debe pertenecer a esta carpeta PSO 4.');
anterior = pwd; cd(carpeta); addpath(carpeta,'-begin');
restaurar_carpeta = onCleanup(@() cd(anterior)); %#ok<NASGU>
assert(license('test','Distrib_Computing_Toolbox'),'PSO4:Toolbox', ...
    'Se requiere Parallel Computing Toolbox para los cuatro procesos.');
assert(~isempty(ver('simulink')) && ~isempty(ver('fuzzy')), ...
    'PSO4:Toolbox','Se requieren Simulink y Fuzzy Logic Toolbox.');
bloqueo = bloquear_pso4(fullfile(carpeta,'PSO4_ACTIVO.lock')); %#ok<NASGU>
if ~isfolder(config.carpeta_salida), mkdir(config.carpeta_salida); end
referencia = preparar_pso4(config);
manifest = manifest_pso4(carpeta);
archivo = fullfile(config.carpeta_salida,'campana_pso.mat');
if isfile(archivo)
    assert(config.reanudar,'PSO4:Existente','Use reanudar=true o una carpeta nueva.');
    datos=load(archivo,'campana'); campana=datos.campana;
    assert(isequaln(campana.config,config) && isequaln(campana.manifest,manifest) && ...
        isequaln(campana.referencia_objetivo,referencia),'PSO4:CampanaDistinta', ...
        'Las fuentes/configuracion cambiaron. Use otra carpeta de resultados.');
else
    campana=struct('version',4,'config',config,'referencia_objetivo',referencia, ...
        'manifest',{manifest},'fecha_inicio',datestr(now,30), ...
        'release_matlab',version('-release'),'eventos_error',{{}});
    campana.ejecuciones=cell(config.numero_ejecuciones,1);
    for k=1:config.numero_ejecuciones
        campana.ejecuciones{k}=struct('numero',k,'semilla',config.semillas(k), ...
            'estado','pendiente','error','');
    end
    fuentes=fullfile(config.carpeta_salida,'fuentes');
    if ~isfolder(fuentes), mkdir(fuentes); end
    for k=1:numel(manifest)
        copyfile(fullfile(carpeta,manifest{k}.nombre),fullfile(fuentes,manifest{k}.nombre));
    end
    guardar_pso4(archivo,'campana',campana);
end
campana=recoger_checkpoints(campana);
guardar_agregado(campana);
pendientes=find(~cellfun(@(r) strcmp(r.estado,'completada'),campana.ejecuciones));
if isempty(pendientes)
    analizar_resultados_pso(campana,fullfile(config.carpeta_salida,'resumen'));
    fprintf('Las %d ejecuciones ya estaban completas; no se simulo de nuevo.\n',config.numero_ejecuciones);
    return;
end

archivo_pausa=fullfile(config.carpeta_salida,'PAUSAR.txt');
if isfile(archivo_pausa), delete(archivo_pausa); end % Ejecutar de nuevo solicita reanudar.
cache_prev=Simulink.fileGenControl('getConfig');
cache_anterior=cache_prev.CacheFolder; codigo_anterior=cache_prev.CodeGenFolder;
restaurar_gen=onCleanup(@() restaurar_cache(cache_anterior,codigo_anterior)); %#ok<NASGU>
Simulink.fileGenControl('set', ...
    'CacheFolder',fullfile(config.carpeta_salida,'cache_control','cache'), ...
    'CodeGenFolder',fullfile(config.carpeta_salida,'cache_control','codigo'),'createDir',true);
fprintf('PSO 4: %d ejecuciones; %d procesos CPU; %d hilo por proceso.\n', ...
    config.numero_ejecuciones,config.numero_trabajadores,config.hilos_por_trabajador);
fprintf('Validando referencia, modo rapido y Fast Restart antes del paralelismo...\n');
campana.preflight=verificar_modelo_pso4(config,referencia);
guardar_pso4(archivo,'campana',campana);
pool=gcp('nocreate');
if isempty(pool)
    pool=parpool('Processes',config.numero_trabajadores);
elseif isa(pool,'parallel.ThreadPool') || pool.NumWorkers~=config.numero_trabajadores || ...
        ~isa(pool.Cluster,'parallel.cluster.Local')
    error('PSO4:Pool', ...
        ['Hay un pool incompatible. Termine sus tareas y ejecute delete(gcp(''nocreate'')); ' ...
        'despues vuelva a iniciar PSO 4. Se necesitan cuatro procesos locales.']);
end
cola=parallel.pool.DataQueue;
panel=[];
if config.mostrar_panel && desktop('inuse')
    try
        panel=figure('Name','PSO 4 - Cuatro procesos CPU','NumberTitle','off', ...
            'MenuBar','none','ToolBar','none','Position',[180 180 650 235]);
        uicontrol(panel,'Style','text','Units','normalized','Position',[.05 .62 .90 .30], ...
            'Tag','avance_pso4','HorizontalAlignment','left','FontSize',10, ...
            'String','Preparando las ejecuciones independientes...');
        uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[.05 .30 .90 .20], ...
            'String','Pausar al terminar la generacion actual', ...
            'Callback',@(~,~) solicitar_pausa_pso4(archivo_pausa));
        uicontrol(panel,'Style','text','Units','normalized','Position',[.05 .05 .90 .18], ...
            'String','La pausa guarda cada PSO; puede tardar lo que resta de una generacion.', ...
            'HorizontalAlignment','left');
        set(panel,'CloseRequestFcn',@(ventana,~) cerrar_panel_pso4(ventana,archivo_pausa));
    catch ME
        warning('PSO4:Panel','No se abrio el panel: %s. Puede usar PAUSAR.txt.',ME.message);
        if ~isempty(panel) && isgraphics(panel), delete(panel); end
        panel=[];
    end
end
afterEach(cola,@(evento) mostrar_progreso_pso4(evento,panel));
futuros={}; numeros=[]; procesado=false(0,1); siguiente=1;
mapa_futuros=containers.Map('KeyType','double','ValueType','any');
limpiar_futuros=onCleanup(@() cancelar_mapa_pso4(mapa_futuros)); %#ok<NASGU>
hay_fallo=false;
while siguiente<=numel(pendientes) || any(~procesado)
    pausa=isfile(archivo_pausa);
    activos=sum(~procesado);
    while ~pausa && ~hay_fallo && siguiente<=numel(pendientes) && activos<config.numero_trabajadores
        numero=pendientes(siguiente); siguiente=siguiente+1;
        fprintf('Asignando ejecucion %d, semilla %d.\n',numero,config.semillas(numero));
        futuro=parfeval(pool,@trabajador_pso4,1,numero,config,cola);
        futuros{end+1}=futuro; numeros(end+1)=numero; procesado(end+1,1)=false; %#ok<AGROW>
        mapa_futuros(numel(futuros))=futuro;
        activos=activos+1;
    end
    cambio=false;
    for j=find(~procesado)'
        futuro=futuros{j};
        if ~strcmp(futuro.State,'finished'), continue; end
        numero=numeros(j);
        try
            registro=fetchOutputs(futuro);
            assert(registro.semilla==config.semillas(numero),'PSO4:Semilla','Semilla inconsistente.');
            campana.ejecuciones{numero}=registro;
            fprintf('Ejecucion %d: %s.\n',numero,registro.estado);
            if strcmp(registro.estado,'fallida'), hay_fallo=true; solicitar_pausa_pso4(archivo_pausa); end
        catch ME
            campana=recoger_checkpoints(campana);
            registro=campana.ejecuciones{numero};
            if ~strcmp(registro.estado,'completada') && ~strcmp(registro.estado,'interrumpida')
                registro.estado='fallida'; registro.error=getReport(ME,'extended','hyperlinks','off');
                campana.ejecuciones{numero}=registro;
            end
            campana.eventos_error{end+1}=struct('numero',numero,'fecha',datestr(now,30), ...
                'mensaje',getReport(ME,'extended','hyperlinks','off'));
            hay_fallo=true; solicitar_pausa_pso4(archivo_pausa);
            fprintf(2,'Error en ejecucion %d: %s\n',numero,ME.message);
        end
        procesado(j)=true; cambio=true;
    end
    if cambio
        assert(isequaln(manifest_pso4(carpeta),manifest),'PSO4:FuenteCambio', ...
            'Cambio una fuente durante la campana. Los checkpoints individuales se conservan.');
        guardar_agregado(campana);
    end
    if (pausa || hay_fallo) && ~any(~procesado), break; end
    drawnow;
    pause(0.2);
end
campana=recoger_checkpoints(campana);
campana.fecha_ultimo_cierre=datestr(now,30);
if all(cellfun(@(r) strcmp(r.estado,'completada'),campana.ejecuciones))
    campana.fecha_fin=datestr(now,30);
end
guardar_agregado(campana);
if ~isempty(panel) && isgraphics(panel)
    h=findobj(panel,'Tag','avance_pso4');
    set(h,'String','Proceso detenido o completado. Revise el resumen y el estado de las ejecuciones.');
    set(findobj(panel,'Style','pushbutton'),'Enable','off');
    set(panel,'CloseRequestFcn',@(ventana,~) delete(ventana));
end
analizar_resultados_pso(campana,fullfile(config.carpeta_salida,'resumen'));
if hay_fallo
    error('PSO4:EjecucionFallida', ...
        'Hubo un error. Se pauso el resto conservando sus checkpoints. Revise estado_ejecuciones.csv.');
end
end

function solicitar_pausa_pso4(archivo_pausa)
fid=fopen(archivo_pausa,'w');
if fid<0, warning('PSO4:Pausa','No se pudo crear %s.',archivo_pausa); return; end
fprintf(fid,'Pausa solicitada %s\n',datestr(now,30)); fclose(fid);
fprintf('Pausa solicitada: se guardara al terminar la generacion de cada PSO activo.\n');
end

function cerrar_panel_pso4(panel,archivo_pausa)
solicitar_pausa_pso4(archivo_pausa);
if isgraphics(panel), delete(panel); end
end

function mostrar_progreso_pso4(evento,panel)
fprintf('[PSO %02d / semilla %d] iteracion %d/%d; J=%.10g', ...
    evento.numero_global,evento.semilla,evento.iteracion,evento.max_iteraciones,evento.mejorJ);
if isfield(evento,'simulaciones_reales')
    fprintf('; simulaciones=%d; cache=%d',evento.simulaciones_reales,evento.aciertos_cache);
end
fprintf('\n');
if ~isempty(panel) && isgraphics(panel)
    h=findobj(panel,'Tag','avance_pso4');
    texto=sprintf('Ultimo avance: PSO %d, semilla %d\nIteracion %d de %d | J = %.10g\nCuatro procesos CPU, un hilo de calculo por proceso.', ...
        evento.numero_global,evento.semilla,evento.iteracion,evento.max_iteraciones,evento.mejorJ);
    set(h,'String',texto);
end
end

function cancelar_mapa_pso4(mapa)
% Captura el contenedor y sus futures, no el workspace del coordinador.
valores=values(mapa);
for k=1:numel(valores)
    try
        if ~strcmp(valores{k}.State,'finished'), cancel(valores{k}); end
    catch
    end
end
end

function validar(c)
validateattributes(c.numero_ejecuciones,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.semillas,{'numeric'},{'vector','numel',c.numero_ejecuciones, ...
    'real','finite','integer','>=',0,'<=',2^32-1});
assert(numel(unique(c.semillas))==c.numero_ejecuciones,'PSO4:Semillas','Use semillas distintas.');
assert(c.numero_trabajadores==4 && c.hilos_por_trabajador==1,'PSO4:Recursos', ...
    'Esta version esta configurada para cuatro procesos y un hilo por proceso.');
validateattributes(c.n_particulas,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.max_iteraciones,{'numeric'},{'scalar','integer','positive'});
end

function campana=recoger_checkpoints(campana)
for k=1:campana.config.numero_ejecuciones
    archivo=fullfile(campana.config.carpeta_salida,'ejecuciones',sprintf('ejecucion_%02d',k),'campana_pso.mat');
    if ~isfile(archivo), continue; end
    datos=load(archivo,'campana'); local=datos.campana;
    assert(numel(local.ejecuciones)==1 && local.config.semillas==campana.config.semillas(k), ...
        'PSO4:Checkpoint','El checkpoint %d no corresponde a su semilla.',k);
    esperado=campana.config;
    esperado.numero_global=k; esperado.carpeta_campana=campana.config.carpeta_salida;
    esperado.archivo_pausa=fullfile(campana.config.carpeta_salida,'PAUSAR.txt');
    esperado.numero_ejecuciones=1; esperado.semillas=campana.config.semillas(k);
    esperado.carpeta_salida=fileparts(archivo);
    esperado.realizar_preflight=false; esperado.generar_resumen=false;
    if ~isfield(esperado,'evaluacion_rapida'), esperado.evaluacion_rapida=true; end
    assert(isequaln(local.config,esperado) && ...
        isequaln(local.referencia_objetivo,campana.referencia_objetivo), ...
        'PSO4:Checkpoint','La configuracion del checkpoint %d es distinta.',k);
    % Los checkpoints completos tambien deben pertenecer a las mismas fuentes.
    for j=1:numel(local.manifest)
        entrada=local.manifest{j};
        [~,nombre,extension]=fileparts(entrada.ruta);
        relativo=[nombre extension];
        coincidencia=find(cellfun(@(x) strcmpi(x.nombre,relativo),campana.manifest),1);
        assert(~isempty(coincidencia) && ...
            isequal(campana.manifest{coincidencia}.contenido,entrada.contenido), ...
            'PSO4:CheckpointFuente','El checkpoint %d usa otra version de %s.',k,relativo);
    end
    registro=local.ejecuciones{1}; registro.numero=k; registro.ruta_checkpoint=archivo;
    campana.ejecuciones{k}=registro;
end
end

function guardar_agregado(campana)
carpeta=campana.config.carpeta_salida;
guardar_pso4(fullfile(carpeta,'campana_pso.mat'),'campana',campana);
N=campana.config.numero_ejecuciones;
estado=cell(N,1); error_texto=cell(N,1); J=nan(N,1); ABC=nan(N,3);
solicitudes=nan(N,1); simulaciones=nan(N,1); cache=nan(N,1);
for k=1:N
    r=campana.ejecuciones{k}; estado{k}=r.estado; error_texto{k}=r.error;
    if strcmp(r.estado,'completada')
        J(k)=r.mejorJ; ABC(k,:)=r.mejorABC; solicitudes(k)=r.evaluaciones;
        if isfield(r,'simulaciones_reales'), simulaciones(k)=r.simulaciones_reales; end
        if isfield(r,'aciertos_cache'), cache(k)=r.aciertos_cache; end
    end
end
tabla=table((1:N)',campana.config.semillas(:),estado,J,ABC(:,1),ABC(:,2),ABC(:,3), ...
    solicitudes,simulaciones,cache,error_texto,'VariableNames', ...
    {'Ejecucion','Semilla','Estado','CostoFinal','A','B','C','SolicitudesCosto', ...
    'SimulacionesRealesBusqueda','AciertosCache','Error'});
writetable(tabla,fullfile(carpeta,'avance_ejecuciones.csv'));
end

function restaurar_cache(cache,codigo)
try
    Simulink.fileGenControl('set','CacheFolder',cache,'CodeGenFolder',codigo,'createDir',true);
catch
end
end
