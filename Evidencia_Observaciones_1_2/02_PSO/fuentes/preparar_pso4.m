function referencia = preparar_pso4(config)
% Reubica una calibracion existente sin recalcular sus denominadores.
carpeta = config.carpeta_proyecto;
archivo_modelo = fullfile(carpeta,'ActiveSuspensionv2.slx');
requeridos = {'ActiveSuspensionv2.slx','suspension.fis','parameters.m', ...
    'referencia_calibrada_origen.mat','pso_una_ejecucion.m','ejecutar_pso_30.m'};
for k = 1:numel(requeridos)
    assert(isfile(fullfile(carpeta,requeridos{k})), ...
        'PSO4:Archivo','Falta %s en la carpeta nueva.',requeridos{k});
end
modelo = 'ActiveSuspensionv2';
if bdIsLoaded(modelo)
    if ~strcmpi(get_param(modelo,'FileName'),archivo_modelo)
        error('PSO4:ModeloAbierto', ...
            ['Hay otra copia de ActiveSuspensionv2 abierta. Guarde y cierre ' ...
            'esa copia y ejecute de nuevo desde PSO 4. No se cierra automaticamente.']);
    end
    assert(strcmp(get_param(modelo,'Dirty'),'off'),'PSO4:ModeloSinGuardar', ...
        'Guarde o descarte los cambios pendientes del modelo antes de ejecutar.');
end
load_system(archivo_modelo);
assert(strcmp(get_param(modelo,'Dirty'),'off'),'PSO4:ModeloSinGuardar', ...
    'El modelo tiene cambios sin guardar.');
fuente = load(fullfile(carpeta,'referencia_calibrada_origen.mat'),'referencia_objetivo');
referencia = fuente.referencia_objetivo;
actual = configuracion_modelo_objetivo(modelo);
anterior = referencia.configuracion_modelo;
anterior.archivo = actual.archivo;
if ~isfield(anterior,'SimulationMode')
    anterior.SimulationMode = actual.SimulationMode;
end
assert(isequaln(orderfields(anterior),orderfields(actual)), ...
    'PSO4:Calibracion', ...
    'La carretera, solver o ventana no coinciden con la referencia calibrada.');
referencia.configuracion_modelo = actual;
% Cargar parametros SOLO desde el proyecto; sim recibe los valores calibrados.
esperado = fullfile(carpeta,'parameters.m');
assert(strcmpi(which('parameters'),esperado),'PSO4:Path', ...
    'parameters.m se resuelve fuera de PSO 4.');
evalin('base','parameters;');
campos = fieldnames(referencia.parametros_fisicos);
for k = 1:numel(campos)
    valor = evalin('base',campos{k});
    assert(isequaln(valor,referencia.parametros_fisicos.(campos{k})), ...
        'PSO4:Parametros','El parametro %s no coincide con la calibracion.',campos{k});
end
if config.usar_cache_exacta
    fuentes = actual.fuentes;
    pulso = false; seleccion_pulso = false;
    for k = 1:numel(fuentes)
        item = fuentes{k};
        pulso = pulso || strcmp(item.tipo,'DiscretePulseGenerator');
        if strcmp(item.tipo,'ManualSwitch') && isfield(item,'sw')
            seleccion_pulso = strcmp(item.sw,'1');
        end
    end
    assert(pulso && seleccion_pulso,'PSO4:CacheEstocastica', ...
        ['La cache exacta se preparo para el pulso determinista seleccionado. ' ...
        'Para otra carretera, desactive usar_cache_exacta y valide el escenario.']);
end
if isfile(config.archivo_referencia)
    datos = load(config.archivo_referencia,'referencia_objetivo');
    assert(isequaln(datos.referencia_objetivo,referencia),'PSO4:ReferenciaCambio', ...
        'La referencia local difiere de la copia de calibracion. No se sobreescribe.');
else
    guardar_pso4(config.archivo_referencia,'referencia_objetivo',referencia);
end
end
