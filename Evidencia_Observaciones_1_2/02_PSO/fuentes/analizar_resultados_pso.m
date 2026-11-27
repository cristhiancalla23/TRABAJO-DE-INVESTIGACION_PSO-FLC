function resumen = analizar_resultados_pso(origen, carpeta_salida)
%ANALIZAR_RESULTADOS_PSO Tablas, dispersion y graficos de una campana PSO.
% analizar_resultados_pso('.../campana_pso.mat')
% resumen = analizar_resultados_pso(campana, '.../resumen');
% No ejecuta Simulink ni requiere Statistics and Machine Learning Toolbox.
% Los percentiles interpolan la muestra ordenada en h=1+(n-1)*p.
% P2.5 y P97.5 son percentiles empiricos; NO intervalos de confianza.

if ischar(origen) || (isstring(origen) && isscalar(origen))
    archivo = char(origen);
    datos = load(archivo,'campana');
    if ~isfield(datos,'campana')
        error('PSO:Analisis','El archivo debe contener la variable campana.');
    end
    campana = datos.campana;
    carpeta_base = fileparts(archivo);
    if isempty(carpeta_base), carpeta_base = pwd; end
else
    campana = origen;
    carpeta_base = pwd;
end
if nargin < 2 || isempty(carpeta_salida)
    carpeta_salida = fullfile(carpeta_base,'resumen');
end
if ~isstruct(campana) || ~all(isfield(campana,{'config','ejecuciones'})) || ...
        ~iscell(campana.ejecuciones)
    error('PSO:Analisis','Estructura de campana incompatible.');
end
if ~isfolder(carpeta_salida), mkdir(carpeta_salida); end
n_objetivo = campana.config.numero_ejecuciones;
if numel(campana.ejecuciones) ~= n_objetivo
    error('PSO:Analisis','El numero de registros no coincide con la configuracion.');
end

estado = repmat({'pendiente'},n_objetivo,1);
mensaje = repmat({''},n_objetivo,1);
semillas = double(campana.config.semillas(:));
if numel(semillas) ~= n_objetivo || numel(unique(semillas)) ~= n_objetivo
    error('PSO:Analisis','Las semillas deben ser distintas y cubrir cada ejecucion.');
end
validos = false(n_objetivo,1);
for k = 1:n_objetivo
    registro = campana.ejecuciones{k};
    if isempty(registro), continue; end
    if isfield(registro,'estado'), estado{k} = char(registro.estado); end
    if isfield(registro,'error'), mensaje{k} = char(registro.error); end
    validos(k) = strcmp(estado{k},'completada');
end
tabla_estado = table((1:n_objetivo)',semillas,estado,mensaje, ...
    'VariableNames',{'Ejecucion','Semilla','Estado','Error'});
writetable(tabla_estado,fullfile(carpeta_salida,'estado_ejecuciones.csv'));

indices = find(validos);
n = numel(indices);
nombres = {'CostoFinal','A','B','C','Tiempo_s','CostoValidado','CostoMATLAB','DiferenciaCosto', ...
    'ISE_m2s','Pico_m','RMS_m','ReduccionRMS_pct','ReduccionPico_pct', ...
    'ObjSimulink','FuerzaRMS_N','FuerzaPico_N','Esfuerzo_N2s','EvaluacionesBusqueda', ...
    'SimulacionesRealesBusqueda','AciertosCache'};
valores = nan(n,numel(nombres));
historiales = nan(campana.config.max_iteraciones+1,n);
for j = 1:n
    k = indices(j);
    registro = campana.ejecuciones{k};
    if isfield(registro,'semilla') && registro.semilla ~= semillas(k)
        error('PSO:Analisis','Semilla inconsistente en la ejecucion %d.',k);
    end
    necesarios = {'mejorJ','mejorABC','historialJ','evaluaciones','tiempo_segundos','validacion'};
    if ~all(isfield(registro,necesarios)) || ~isfinite(registro.mejorJ) || ...
            numel(registro.mejorABC) ~= 3 || any(~isfinite(registro.mejorABC(:)))
        error('PSO:Analisis','La ejecucion %d se marca completada pero sus datos son invalidos.',k);
    end
    historial = registro.historialJ(:);
    if numel(historial) ~= size(historiales,1) || any(~isfinite(historial))
        error('PSO:Analisis','Historial incompleto o no finito en la ejecucion %d.',k);
    end
    historiales(:,j) = historial;
    v = registro.validacion;
    valores(j,:) = [registro.mejorJ, registro.mejorABC(:)',registro.tiempo_segundos, ...
        campo(v,'J'),campo(v,'J_MATLAB'),campo(v,'diferencia_costo'),campo(v,'ISE'),campo(v,'pico'), ...
        campo(v,'RMS_desplazamiento'),campo(v,'reduccion_RMS_porcentaje'), ...
        campo(v,'reduccion_pico_porcentaje'),campo(v,'J_obj_simulink'), ...
        campo(v,'fuerza_RMS'),campo(v,'fuerza_pico'),campo(v,'esfuerzo_cuadratico'), ...
        registro.evaluaciones,campo(registro,'simulaciones_reales'),campo(registro,'aciertos_cache')];
end
tabla_resultados = [table(indices,semillas(indices), ...
    'VariableNames',{'Ejecucion','Semilla'}),array2table(valores,'VariableNames',nombres)];
writetable(tabla_resultados,fullfile(carpeta_salida,'resultados_ejecuciones.csv'));
tabla_convergencia = resumir_convergencia(historiales);
writetable(tabla_convergencia,fullfile(carpeta_salida,'convergencia_resumen.csv'));

% Incluye N por variable: una fuerza no registrada no se interpreta como cero.
columnas = {'N','Media','DesvEstandarMuestral','VarianzaMuestral','Mediana', ...
    'Minimo','Maximo','Q1','Q3','IQR','Percentil2_5','Percentil97_5'};
estadisticas = nan(numel(nombres),numel(columnas));
for j = 1:numel(nombres)
    x = valores(:,j);
    x = x(isfinite(x));
    estadisticas(j,1) = numel(x);
    if isempty(x), continue; end
    q = cuantiles(x,[0.025 0.25 0.5 0.75 0.975]);
    if numel(x) < 2
        desviacion = NaN; varianza = NaN;
    else
        desviacion = std(x,0); varianza = var(x,0);
    end
    estadisticas(j,:) = [numel(x),mean(x),desviacion,varianza,q(3), ...
        min(x),max(x),q(2),q(4),q(4)-q(2),q(1),q(5)];
end
tabla_estadisticas = [table(nombres(:),'VariableNames',{'Variable'}), ...
    array2table(estadisticas,'VariableNames',columnas)];
writetable(tabla_estadisticas,fullfile(carpeta_salida,'estadisticas_resumen.csv'));

resumen = struct;
resumen.numero_objetivo = n_objetivo;
resumen.numero_completadas = n;
resumen.numero_fallidas = sum(strcmp(estado,'fallida'));
resumen.numero_pendientes = sum(~validos & ~strcmp(estado,'fallida'));
resumen.campana_completa = n == n_objetivo && n >= 30;
resumen.estadisticas = tabla_estadisticas;
resumen.IC95_media_costo = [NaN NaN];
resumen.bootstrap_semilla = 20261102;
resumen.bootstrap_replicas = 2000;
if n >= 2
    % Un flujo privado evita alterar el estado aleatorio del optimizador.
    flujo = RandStream('mt19937ar','Seed',resumen.bootstrap_semilla);
    muestras_indices = 1 + floor(rand(flujo,n,resumen.bootstrap_replicas)*n);
    muestras = reshape(valores(muestras_indices(:),1),n,resumen.bootstrap_replicas);
    medias_bootstrap = mean(muestras,1);
    resumen.IC95_media_costo = cuantiles(medias_bootstrap,[0.025 0.975]);
end
if n > 0, media_costo = mean(valores(:,1)); else, media_costo = NaN; end
tabla_intervalo = table(n,media_costo,resumen.IC95_media_costo(1), ...
    resumen.IC95_media_costo(2),resumen.bootstrap_replicas,resumen.bootstrap_semilla, ...
    'VariableNames',{'N','MediaCosto','IC95BootstrapInferior','IC95BootstrapSuperior', ...
    'ReplicasBootstrap','SemillaBootstrap'});
writetable(tabla_intervalo,fullfile(carpeta_salida,'intervalo_media_costo.csv'));
resumen.errores_graficos = '';
if n > 0
    try
        graficos(valores,historiales,tabla_convergencia,semillas(indices),nombres,carpeta_salida,n_objetivo);
    catch ME
        resumen.errores_graficos = getReport(ME,'basic','hyperlinks','off');
        warning('PSO:Graficos','Se guardaron las tablas, pero fallaron graficos: %s',ME.message);
    end
end
save(fullfile(carpeta_salida,'estadisticas_pso.mat'), ...
    'resumen','tabla_resultados','tabla_estadisticas','tabla_estado','tabla_intervalo','tabla_convergencia');
escribir_informe(campana,resumen,valores,indices,semillas,carpeta_salida);
fprintf('\nCampana: %d/%d ejecuciones completadas; %d fallidas.\n', ...
    n,n_objetivo,resumen.numero_fallidas);
disp(tabla_estadisticas(1:4,:));
fprintf('Resultados y graficos: %s\n',carpeta_salida);
end

function valor = campo(estructura,nombre)
valor = NaN;
if isfield(estructura,nombre)
    candidato = estructura.(nombre);
    if isnumeric(candidato) && isscalar(candidato) && isreal(candidato) && isfinite(candidato)
        valor = double(candidato);
    end
end
end

function q = cuantiles(x,p)
% Interpolacion lineal explicita; extremos en la primera/ultima observacion.
x = sort(x(:));
q = nan(size(p));
if isempty(x), return; end
h = 1 + (numel(x)-1)*p;
for k = 1:numel(p)
    inferior = floor(h(k)); superior = ceil(h(k));
    q(k) = x(inferior) + (h(k)-inferior)*(x(superior)-x(inferior));
end
end

function tabla = resumir_convergencia(historiales)
iter = (0:size(historiales,1)-1)';
q = nan(numel(iter),3);
for k = 1:numel(iter)
    q(k,:) = cuantiles(historiales(k,:),[0.25 0.5 0.75]);
end
tabla = table(iter,q(:,1),q(:,2),q(:,3), ...
    'VariableNames',{'Iteracion','Q1','Mediana','Q3'});
end

function graficos(valores,historiales,tabla_convergencia,semillas,nombres,carpeta,n_objetivo)
n = size(valores,1);
etiqueta = sprintf('%d de %d ejecuciones completadas',n,n_objetivo);
color = [0.12 0.38 0.64];

fig = figure('Visible','off','Color','w','Position',[100 100 650 460]);
cierre = onCleanup(@() close(fig));
ax = axes(fig); caja(ax,valores(:,1),'J',color);
ylabel(ax,'Costo final adimensional'); title(ax,['Dispersion del costo: ' etiqueta]);
guardar_figura(fig,carpeta,'caja_costo_final'); clear cierre;

fig = figure('Visible','off','Color','w','Position',[100 100 1200 420]);
cierre = onCleanup(@() close(fig));
for j = 1:3
    ax = subplot(1,3,j,'Parent',fig);
    caja(ax,valores(:,j+1),nombres{j+1},color);
    ylabel(ax,['Factor ' nombres{j+1}]); title(ax,['Distribucion de ' nombres{j+1}]);
end
guardar_figura(fig,carpeta,'cajas_factores_ABC'); clear cierre;

iter = tabla_convergencia.Iteracion;
q = [tabla_convergencia.Q1,tabla_convergencia.Mediana,tabla_convergencia.Q3];
fig = figure('Visible','off','Color','w','Position',[100 100 800 480]);
cierre = onCleanup(@() close(fig));
ax = axes(fig); hold(ax,'on');
plot(ax,iter,historiales,'Color',[0.8 0.8 0.8],'LineWidth',0.5,'HandleVisibility','off');
banda = patch(ax,[iter;flipud(iter)],[q(:,1);flipud(q(:,3))],color, ...
    'FaceAlpha',0.2,'EdgeColor','none');
mediana = plot(ax,iter,q(:,2),'Color',color,'LineWidth',2);
xlabel(ax,'Iteracion (0 = poblacion inicial)'); ylabel(ax,'Mejor costo acumulado');
title(ax,['Convergencia: ' etiqueta]); grid(ax,'on');
legend(ax,[mediana banda],{'Mediana','Percentiles 25-75'},'Location','best');
guardar_figura(fig,carpeta,'convergencia_30_ejecuciones'); clear cierre;

fig = figure('Visible','off','Color','w','Position',[100 100 1100 440]);
cierre = onCleanup(@() close(fig));
ax = subplot(1,2,1,'Parent',fig);
plot(ax,semillas,valores(:,1),'o','Color',color,'MarkerFaceColor',color);
xlabel(ax,'Semilla del PSO'); ylabel(ax,'Costo final'); title(ax,'Resultado por semilla'); grid(ax,'on');
ax = subplot(1,2,2,'Parent',fig);
histogram(ax,valores(:,1),max(1,ceil(sqrt(n))),'FaceColor',color);
xlabel(ax,'Costo final'); ylabel(ax,'Numero de ejecuciones'); title(ax,'Distribucion empirica'); grid(ax,'on');
guardar_figura(fig,carpeta,'costos_por_semilla_distribucion'); clear cierre;
end

function caja(ax,x,etiqueta,color)
% Caja Tukey manual: evita depender de la funcion boxplot y su toolbox.
x = x(isfinite(x)); x = x(:); hold(ax,'on');
q = cuantiles(x,[0.25 0.5 0.75]); amplitud = q(3)-q(1);
interiores = x(x >= q(1)-1.5*amplitud & x <= q(3)+1.5*amplitud);
minimo = min(interiores); maximo = max(interiores);
patch(ax,[0.78 1.22 1.22 0.78],[q(1) q(1) q(3) q(3)],color, ...
    'FaceAlpha',0.2,'EdgeColor',color);
plot(ax,[0.78 1.22],[q(2) q(2)],'Color',color,'LineWidth',2);
plot(ax,[1 1],[minimo q(1)],'Color',color);
plot(ax,[1 1],[q(3) maximo],'Color',color);
plot(ax,[0.9 1.1],[minimo minimo],'Color',color);
plot(ax,[0.9 1.1],[maximo maximo],'Color',color);
desfase = linspace(-0.075,0.075,numel(x))';
plot(ax,1+desfase,x,'.','Color',color,'MarkerSize',10);
xlim(ax,[0.5 1.5]); xticks(ax,1); xticklabels(ax,{etiqueta}); grid(ax,'on');
if max(x) == min(x)
    margen = max(1e-6,0.05*max(1,abs(x(1))));
    ylim(ax,[x(1)-margen x(1)+margen]);
end
end

function guardar_figura(fig,carpeta,nombre)
savefig(fig,fullfile(carpeta,[nombre '.fig']));
print(fig,fullfile(carpeta,[nombre '.png']),'-dpng','-r250');
end

function escribir_informe(campana,resumen,valores,indices,semillas,carpeta)
fid = fopen(fullfile(carpeta,'informe_observacion_2.txt'),'w','n','UTF-8');
if fid < 0, error('PSO:Informe','No se pudo escribir el informe.'); end
cierre = onCleanup(@() fclose(fid)); %#ok<NASGU>
n = resumen.numero_completadas;
fprintf(fid,'RESULTADOS ESTADISTICOS DEL PSO - OBSERVACION 2\n\n');
if resumen.campana_completa
    fprintf(fid,'Estado: campana completa, %d ejecuciones independientes registradas.\n',n);
else
    fprintf(fid,'ESTADO PARCIAL: %d de %d ejecuciones completadas.\n',n,resumen.numero_objetivo);
    fprintf(fid,'Este informe parcial no satisface el requisito de al menos 30 ejecuciones.\n');
end
fprintf(fid,'Fallidas: %d; pendientes/no completadas: %d.\n', ...
    resumen.numero_fallidas,resumen.numero_pendientes);
fprintf(fid,'Particulas: %d; iteraciones por busqueda: %d.\n', ...
    campana.config.n_particulas,campana.config.max_iteraciones);
if isfield(campana.config,'manejo_limites')
    fprintf(fid,'Variante: limites=%s; amortiguacion=%.6g; velocidad maxima=%.6g del rango.\n', ...
        campana.config.manejo_limites,campana.config.amortiguacion_reflexion, ...
        campana.config.fraccion_velocidad_maxima);
    fprintf(fid,['EvaluacionesBusqueda cuenta solicitudes del PSO. SimulacionesRealesBusqueda cuenta ' ...
        'llamadas al modelo; AciertosCache cuenta reutilizaciones EXACTAS. La validacion final es adicional.\n']);
end
if isfield(campana.config,'numero_trabajadores')
    fprintf(fid,'Ejecucion paralela: %d procesos, %d hilo por proceso; Fast Restart=%d.\n', ...
        campana.config.numero_trabajadores,campana.config.hilos_por_trabajador, ...
        campana.config.usar_fast_restart);
    fprintf(fid,'Tiempo_s corresponde a cada busqueda y validacion; su suma no es la duracion de la campana paralela.\n');
end
if isfield(campana.config,'origen_costo')
    fprintf(fid,'Origen del costo final seleccionado: %s.\n',char(campana.config.origen_costo));
end
fprintf(fid,['CostoValidado usa el origen seleccionado. CostoMATLAB, ObjSimulink y DiferenciaCosto ' ...
    'permiten contrastar obj con la integral trapz de MATLAB.\n']);
if isfield(campana,'referencia_objetivo')
    r = campana.referencia_objetivo;
    fprintf(fid,'alpha = %.12g; ISE pasiva = %.12g; pico pasivo = %.12g.\n', ...
        r.alpha,r.ISE_pasiva,r.pico_pasiva);
end
fprintf(fid,'Semillas de ejecuciones completadas: ');
fprintf(fid,'%.0f ',semillas(indices)); fprintf(fid,'\n\n');
fprintf(fid,'La desviacion estandar y varianza usan el divisor n-1.\n');
fprintf(fid,'Los cuantiles interpolan linealmente en h=1+(n-1)*p.\n');
fprintf(fid,'Percentiles 2.5 y 97.5: dispersion empirica; no intervalos de confianza.\n');
fprintf(fid,['El IC95 de la MEDIA se estima aparte mediante bootstrap percentil: %d remuestras, ' ...
    'semilla privada %d. Requiere interpretar las ejecuciones como replicas independientes.\n'], ...
    resumen.bootstrap_replicas,resumen.bootstrap_semilla);
fprintf(fid,'Las tablas incluyen N por variable. Datos opcionales ausentes permanecen NaN.\n');
fprintf(fid,'El esfuerzo integral(Fa^2 dt) se expresa en N^2*s, no en joules.\n\n');
if n == 0
    fprintf(fid,'No hay ejecuciones completadas para calcular resultados.\n');
    return;
end
costos = valores(:,1); [mejor,idx_mejor] = min(costos); [peor,idx_peor] = max(costos);
if n > 1, desviacion = std(costos,0); else, desviacion = NaN; end
fprintf(fid,'Costo final: media %.12g; desviacion estandar %.12g; mediana %.12g.\n', ...
    mean(costos),desviacion,median(costos));
fprintf(fid,'IC95 bootstrap percentil de la media: [%.12g, %.12g].\n',resumen.IC95_media_costo);
fprintf(fid,'Mejor costo %.12g: ejecucion %d, semilla %.0f, A/B/C = %.12g %.12g %.12g.\n', ...
    mejor,indices(idx_mejor),semillas(indices(idx_mejor)),valores(idx_mejor,2:4));
fprintf(fid,'Peor costo %.12g: ejecucion %d, semilla %.0f.\n\n', ...
    peor,indices(idx_peor),semillas(indices(idx_peor)));
fprintf(fid,'PARRAFO BASE PARA EL MANUSCRITO (revisar antes de incorporarlo):\n');
fprintf(fid,['Se realizaron %d ejecuciones del PSO con semillas distintas y la misma ' ...
    'configuracion de entrenamiento. Cada busqueda utilizo %d particulas y %d ' ...
    'iteraciones. El costo final tuvo una media de %.8g y una desviacion ' ...
    'estandar muestral de %.8g; el mejor y peor costo fueron %.8g y %.8g. ' ...
    'Se presentan diagramas de caja del costo y de los factores A, B y C, ' ...
    'junto con la mediana y el rango intercuartil de la convergencia.\n\n'], ...
    n,campana.config.n_particulas,campana.config.max_iteraciones, ...
    mean(costos),desviacion,mejor,peor);
fprintf(fid,['No se infiere automaticamente robustez ni superioridad a partir de estos datos. ' ...
    'La interpretacion debe examinar la dispersion, los casos extremos y los fallos.\n']);
fprintf(fid,['No se calcularon p-valores: una prueba de significancia requiere definir ' ...
    'una hipotesis o una comparacion especifica.\n']);
if ~isempty(resumen.errores_graficos)
    fprintf(fid,'\nERROR EN GRAFICOS:\n%s\n',resumen.errores_graficos);
end
end
