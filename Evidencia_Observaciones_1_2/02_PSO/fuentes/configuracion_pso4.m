function config = configuracion_pso4
% PSO 4: cuatro procesos CPU, una busqueda independiente por proceso.
carpeta = fileparts(mfilename('fullpath'));
config.numero_ejecuciones = 30;
config.semillas = 1:30;
config.n_particulas = 20;
config.max_iteraciones = 50;
config.limite_inferior = [0 0 0];
config.limite_superior = [15 15 5000];
config.w = 0.9;
config.c1 = 1.2;
config.c2 = 1.4;
config.fraccion_velocidad_inicial = 0.1;
% Variante declarada respecto al PSO anterior. No hay parada anticipada.
config.manejo_limites = 'rebote';
config.amortiguacion_reflexion = 0.5;
config.fraccion_velocidad_maxima = 0.2;
config.usar_cache_exacta = true; % Solo carretera/condiciones deterministas fijas.
config.origen_costo = 'simulink';
config.modo_evaluacion = 'rapida'; % Validaciones inicial/final siempre completas.
config.evaluacion_rapida = true;
config.usar_fast_restart = true;
config.numero_trabajadores = 4;
config.hilos_por_trabajador = 1;
config.carpeta_proyecto = carpeta;
config.archivo_referencia = fullfile(carpeta,'referencia_objetivo_normalizado.mat');
config.carpeta_salida = fullfile(carpeta,'resultados_30_ejecuciones');
config.reanudar = true;
config.mostrar_panel = true;
config.generar_resumen = false; % El coordinador genera el resumen conjunto.
config.realizar_preflight = false; % Verificacion central antes de lanzar workers.
config.tolerancia_absoluta = 1e-4;
config.tolerancia_relativa = 1e-3;
end
