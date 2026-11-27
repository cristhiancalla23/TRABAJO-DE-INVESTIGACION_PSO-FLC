function configuracion = configuracion_modelo_objetivo(modelo)
% Registra fuentes, solver y seleccion de carretera para evitar mezclar casos.
load_system(modelo);
configuracion.modelo = get_param(modelo,'Name');
configuracion.archivo = get_param(modelo,'FileName');
campos = {'StartTime','StopTime','SolverType','Solver','FixedStep','SimulationMode'};
for k = 1:numel(campos)
    configuracion.(campos{k}) = get_param(modelo,campos{k});
end
bloques = sort(find_system(modelo,'SearchDepth',1,'Type','Block'));
fuentes = {};
campos_fuente = {'Amplitude','Period','PulseWidth','PhaseDelay', ...
    'PulseType','sw','Cov','Ts','seed'};
for k = 1:numel(bloques)
    bloque = bloques{k};
    tipo = get_param(bloque,'BlockType');
    es_fuente = any(strcmp(tipo,{'ManualSwitch','DiscretePulseGenerator','RandomNumber','WhiteNoise'}));
    if strcmp(tipo,'Reference')
        es_fuente = contains(get_param(bloque,'SourceBlock'),'White Noise');
    end
    if ~es_fuente, continue; end
    item = struct('bloque',bloque,'tipo',tipo);
    for j = 1:numel(campos_fuente)
        try
            item.(campos_fuente{j}) = get_param(bloque,campos_fuente{j});
        catch
            % Cada tipo de fuente expone parametros diferentes.
        end
    end
    fuentes{end+1} = item; %#ok<AGROW>
end
configuracion.fuentes = fuentes;
end
