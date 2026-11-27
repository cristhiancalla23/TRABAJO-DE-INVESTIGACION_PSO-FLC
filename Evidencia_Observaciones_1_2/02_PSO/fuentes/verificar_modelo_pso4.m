function comprobaciones = verificar_modelo_pso4(config, referencia)
% Dos controles: completa vs rapida, repeticion y aislamiento de las ganancias.
modelo = referencia.modelo;
estado_fast = get_param(modelo,'FastRestart');
restaurar = onCleanup(@() set_param(modelo,'FastRestart',estado_fast)); %#ok<NASGU>
set_param(modelo,'FastRestart','off');
config_completa = config; config_completa.modo_evaluacion = 'completa';
config_rapida = config; config_rapida.modo_evaluacion = 'rapida';
ganancias = [0 0 0;10 10 4444];
comprobaciones = cell(2,1);
for k = 1:2
    reloj = tic;
    [Jmat,~,salida] = evaluar_particula_normalizada(ganancias(k,:),referencia,config_completa);
    tiempo_normal = toc(reloj);
    obj = salida.get('obj'); Jobj = double(obj.Data(end));
    tolerancia = config.tolerancia_absoluta + config.tolerancia_relativa*max(abs([Jmat Jobj]));
    assert(abs(Jmat-Jobj)<=tolerancia,'PSO4:Normalizacion', ...
        'La funcion objetivo de Simulink no coincide con la normalizada MATLAB.');
    if k == 1
        assert(abs(Jobj-1)<=config.tolerancia_absoluta+config.tolerancia_relativa, ...
            'PSO4:Pasiva','Con ganancias cero se esperaba J cercano a 1.');
        a=salida.get(referencia.senal_activa); p=salida.get(referencia.senal_pasiva);
        assert(max(abs(a.Data(:)-p.Data(:)))<=1e-7+1e-5*max(abs(p.Data(:))), ...
            'PSO4:Pasiva','Las senales activa y pasiva no coinciden con C=0.');
    end
    comprobaciones{k} = struct('ABC',ganancias(k,:),'J_obj',Jobj,'J_MATLAB',Jmat, ...
        'J_rapida',NaN,'J_repetida',NaN,'tiempo_normal_s',tiempo_normal, ...
        'tiempo_primera_fast_s',NaN,'tiempo_repetida_fast_s',NaN);
end
% Mantener compilacion activa AL CAMBIAR ganancias y al volver a cero.
% Cero -> activas -> activas -> cero detecta reuso accidental de parametros/estado.
if config.usar_fast_restart, set_param(modelo,'FastRestart','on'); end
secuencia=[1 2 2 1];
visitas=zeros(2,1);
for indice=secuencia
    reloj=tic;
    J=evaluar_particula_normalizada(ganancias(indice,:),referencia,config_rapida);
    duracion=toc(reloj);
    objetivo=comprobaciones{indice}.J_obj;
    tolerancia=config.tolerancia_absoluta+config.tolerancia_relativa*abs(objetivo);
    assert(abs(J-objetivo)<=tolerancia,'PSO4:Equivalencia', ...
        'El modo rapido/Fast Restart no aplica las ganancias o no reproduce el costo.');
    visitas(indice)=visitas(indice)+1;
    if visitas(indice)==1
        comprobaciones{indice}.J_rapida=J;
        comprobaciones{indice}.tiempo_primera_fast_s=duracion;
    else
        comprobaciones{indice}.J_repetida=J;
        comprobaciones{indice}.tiempo_repetida_fast_s=duracion;
    end
end
for k=1:2
    fprintf('Control [%g %g %g]: J=%.12g; completa %.2fs; repetida %.2fs.\n', ...
        ganancias(k,:),comprobaciones{k}.J_obj,comprobaciones{k}.tiempo_normal_s, ...
        comprobaciones{k}.tiempo_repetida_fast_s);
end
end
