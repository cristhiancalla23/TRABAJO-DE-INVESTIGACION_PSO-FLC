function [J, detalle, salida] = evaluar_particula_normalizada(ganancias, referencia_objetivo, opciones)
% Evalua [A B C] sin modificar el workspace base ni guardar el modelo.
% modo_evaluacion='rapida': costo oficial obj final, para la busqueda.
% modo_evaluacion='completa' (predeterminado): senales completas y trapz.
% La plantilla de SimulationInput se reutiliza dentro de cada proceso.
if nargin < 3 || isempty(opciones), opciones = struct; end
if ~isfield(opciones,'modo_evaluacion'), opciones.modo_evaluacion = 'completa'; end
modo = char(opciones.modo_evaluacion);
assert(any(strcmp(modo,{'rapida','completa'})), ...
    'Objetivo:Modo','modo_evaluacion debe ser rapida o completa.');
validateattributes(ganancias,{'numeric'},{'real','finite','vector','numel',3,'nonnegative'});
if ganancias(3) > 5000
    error('Objetivo:Fuerza','C debe ser menor o igual que 5000.');
end
campos = {'modelo','senal_activa','senal_pasiva','parametros_fisicos','configuracion_modelo'};
if ~isstruct(referencia_objetivo) || ~isscalar(referencia_objetivo) || ...
        ~all(isfield(referencia_objetivo,campos))
    error('Objetivo:Calibracion','Falta la referencia normalizada compatible.');
end
modelo = referencia_objetivo.modelo;
persistent plantilla referencia_plantilla
nueva = isempty(plantilla) || ~isequaln(referencia_plantilla,referencia_objetivo);
if nueva || strcmp(modo,'completa')
    actual = configuracion_modelo_objetivo(modelo);
    if ~isequaln(actual,referencia_objetivo.configuracion_modelo)
        error('Objetivo:Configuracion', ...
            'Cambio el modelo, solver, fuente o interruptor respecto de la calibracion.');
    end
end
if nueva
    plantilla = Simulink.SimulationInput(modelo);
    plantilla = plantilla.setModelParameter('ReturnWorkspaceOutputs','on');
    parametros = referencia_objetivo.parametros_fisicos;
    nombres = fieldnames(parametros);
    for k = 1:numel(nombres)
        plantilla = plantilla.setVariable(nombres{k},parametros.(nombres{k}));
    end
    plantilla = plantilla.setVariable('referencia_objetivo',referencia_objetivo);
    referencia_plantilla = referencia_objetivo;
end
entrada = plantilla;
entrada = entrada.setVariable('A',ganancias(1));
entrada = entrada.setVariable('B',ganancias(2));
entrada = entrada.setVariable('C',ganancias(3));
salida = sim(entrada);
obj = salida.get('obj');
if ~isa(obj,'timeseries') || isempty(obj.Data) || ...
        ~isnumeric(obj.Data) || ~isreal(obj.Data) || ...
        numel(obj.Data) ~= numel(obj.Time) || any(~isfinite(obj.Data(:)))
    error('PSO:Obj','obj debe ser una Timeseries escalar, real y finita.');
end
J_obj = double(obj.Data(end));
if ~isscalar(J_obj) || ~isfinite(J_obj) || J_obj < 0
    error('PSO:Obj','El costo obj final debe ser real, finito y no negativo.');
end
if strcmp(modo,'rapida')
    J = J_obj;
    detalle = struct('modo','rapida','J_obj_simulink',J_obj);
    return;
end
activa = salida.get(referencia_objetivo.senal_activa);
pasiva = salida.get(referencia_objetivo.senal_pasiva);
[J_pasiva, detalle_pasiva] = funcion_objetivo_normalizada(pasiva,referencia_objetivo);
if abs(detalle_pasiva.ISE_normalizado-1) > 1e-4 || ...
        abs(detalle_pasiva.pico_normalizado-1) > 1e-4
    error('Objetivo:ReferenciaCambio','La respuesta pasiva ya no coincide con la calibracion.');
end
[J, detalle] = funcion_objetivo_normalizada(activa,referencia_objetivo);
detalle.J_pasiva = J_pasiva;
detalle.J_obj_simulink = J_obj;
detalle.modo = 'completa';
end
