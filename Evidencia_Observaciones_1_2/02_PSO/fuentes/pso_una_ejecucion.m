function resultado = pso_una_ejecucion(funcion_costo, config, semilla, al_guardar, estado_inicial)
%PSO_UNA_EJECUCION PSO sincrono con flujo privado y reanudacion exacta.
% evaluaciones cuenta solicitudes de costo; simulaciones_reales cuenta llamadas
% al objetivo. La cache solo es valida para un objetivo DETERMINISTA e inmutable.
% El checkpoint guarda cache, posiciones, velocidades, mejores, RNG y diagnosticos.
if nargin < 4, al_guardar = []; end
if nargin < 5, estado_inicial = []; end
validateattributes(semilla,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',2^32-1});
validateattributes(config.n_particulas,{'numeric'},{'scalar','integer','positive'});
validateattributes(config.max_iteraciones,{'numeric'},{'scalar','integer','positive'});
lb = double(config.limite_inferior(:)');
ub = double(config.limite_superior(:)');
validateattributes(lb,{'numeric'},{'vector','real','finite','nonempty'});
validateattributes(ub,{'numeric'},{'vector','real','finite','numel',numel(lb)});
assert(all(ub>=lb),'PSO:Limites','Los limites superiores deben ser >= a los inferiores.');
validateattributes(config.w,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(config.c1,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(config.c2,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(config.fraccion_velocidad_inicial,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
modo = char(opcion(config,'manejo_limites','rebote'));
assert(any(strcmp(modo,{'rebote','reflexion','recorte'})),'PSO4:Limites', ...
    'manejo_limites debe ser rebote, reflexion o recorte.');
amortiguacion = opcion(config,'amortiguacion_reflexion',0.5);
validateattributes(amortiguacion,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
fraccion_maxima = opcion(config,'fraccion_velocidad_maxima',0.2);
validateattributes(fraccion_maxima,{'numeric'},{'scalar','real','nonnegative'});
assert(~isnan(fraccion_maxima),'PSO4:Velocidad','La fraccion maxima no puede ser NaN.');
usar_cache = opcion(config,'usar_cache_exacta',true);
% Los atributos >= y <= de validateattributes no admiten valores logical.
% Validar forma/tipo primero; el assert acepta solo 0/1 y rechaza NaN/Inf.
validateattributes(usar_cache,{'logical','numeric'},{'scalar','real'});
assert(usar_cache==0 || usar_cache==1,'PSO4:Cache','usar_cache_exacta debe ser logico.');
usar_cache = logical(usar_cache);
n = config.n_particulas; m = numel(lb); K = config.max_iteraciones;
rango = ub-lb;
assert(all(isfinite(rango)),'PSO4:Rango','El ancho del dominio debe ser finito.');
if isinf(fraccion_maxima)
    vmax = inf(1,m); vmax(rango==0) = 0;
else
    vmax = fraccion_maxima*rango;
    assert(all(isfinite(vmax)),'PSO4:Velocidad','El limite de velocidad no es finito.');
end
firma_config = struct('version_motor',4,'n',n,'K',K,'lb',lb,'ub',ub, ...
    'w',config.w,'c1',config.c1,'c2',config.c2, ...
    'velocidad_inicial',config.fraccion_velocidad_inicial, ...
    'manejo_limites',modo,'amortiguacion_reflexion',amortiguacion, ...
    'fraccion_velocidad_maxima',fraccion_maxima,'usar_cache_exacta',usar_cache);
flujo = RandStream('mt19937ar','Seed',semilla);
reloj = tic;
tiempo_anterior = 0;
if isempty(estado_inicial)
    estado = struct;
    estado.config_motor = firma_config;
    estado.semilla = semilla;
    estado.x = lb + rand(flujo,n,m).*rango;
    estado.v = (2*rand(flujo,n,m)-1).*rango*config.fraccion_velocidad_inicial;
    estado.v = min(max(estado.v,-vmax),vmax);
    assert(all(isfinite(estado.v(:))),'PSO4:Velocidad','La velocidad inicial no es finita.');
    estado.pbest = estado.x;
    estado.pbestJ = nan(n,1);
    estado.evaluaciones = 0;
    estado.simulaciones_reales = 0;
    estado.aciertos_cache = 0;
    estado.cache_posiciones = zeros(0,m);
    estado.cache_costos = zeros(0,1);
    estado.historialJ = nan(K+1,1);
    estado.historialABC = nan(K+1,m);
    estado.diagnosticos = struct('iteracion',(0:K)', ...
        'diversidad_normalizada',nan(K+1,m), ...
        'fraccion_limite_inferior',nan(K+1,m), ...
        'fraccion_limite_superior',nan(K+1,m), ...
        'posiciones_unicas',nan(K+1,1),'solicitudes_costo',nan(K+1,1), ...
        'simulaciones_reales',nan(K+1,1),'aciertos_cache',nan(K+1,1));
    for i = 1:n
        estado.pbestJ(i) = evaluar(estado.x(i,:));
    end
    [estado.mejorJ, indice] = min(estado.pbestJ);
    estado.mejorABC = estado.pbest(indice,:);
    estado.iteracion = 0;
    estado.historialJ(1) = estado.mejorJ;
    estado.historialABC(1,:) = estado.mejorABC;
    guardar;
else
    estado = estado_inicial;
    requeridos = {'config_motor','semilla','x','v','pbest','pbestJ','iteracion', ...
        'mejorJ','mejorABC','historialJ','historialABC','evaluaciones', ...
        'estado_aleatorio','tiempo_busqueda_segundos','simulaciones_reales', ...
        'aciertos_cache','cache_posiciones','cache_costos','diagnosticos'};
    assert(isstruct(estado) && isscalar(estado) && all(isfield(estado,requeridos)) && ...
        isequaln(estado.config_motor,firma_config) && estado.semilla==semilla && ...
        isequal(size(estado.x),[n m]) && isequal(size(estado.v),[n m]) && ...
        isequal(size(estado.pbest),[n m]) && numel(estado.pbestJ)==n && ...
        numel(estado.historialJ)==K+1 && isequal(size(estado.historialABC),[K+1 m]) && ...
        isscalar(estado.iteracion) && isfinite(estado.iteracion) && ...
        estado.iteracion>=0 && estado.iteracion<=K && estado.iteracion==fix(estado.iteracion), ...
        'PSO:Checkpoint','El estado no corresponde a esta ejecucion de PSO 4.');
    assert(all(isfinite(estado.x(:))) && all(isfinite(estado.v(:))) && ...
        all(all(estado.x>=lb & estado.x<=ub)) && ...
        all(isfinite(estado.pbestJ(:))) && all(estado.pbestJ(:)>=0) && ...
        estado.evaluaciones==n*(estado.iteracion+1) && ...
        estado.simulaciones_reales+estado.aciertos_cache==estado.evaluaciones && ...
        size(estado.cache_posiciones,2)==m && ...
        size(estado.cache_posiciones,1)==numel(estado.cache_costos), ...
        'PSO:Checkpoint','El checkpoint tiene datos o contadores inconsistentes.');
    flujo.State = estado.estado_aleatorio;
    tiempo_anterior = estado.tiempo_busqueda_segundos;
end

for iteracion = estado.iteracion+1:K
    % Se mantiene la actualizacion sincrona y la ecuacion original de PSO.
    r1 = rand(flujo,n,m); r2 = rand(flujo,n,m);
    estado.v = config.w*estado.v + ...
        config.c1*r1.*(estado.pbest-estado.x) + ...
        config.c2*r2.*(estado.mejorABC-estado.x);
    estado.v = min(max(estado.v,-vmax),vmax);
    candidato = estado.x+estado.v;
    if any(~isfinite(candidato(:))) || any(~isfinite(estado.v(:)))
        error('PSO4:Dinamica','La actualizacion produjo posiciones o velocidades no finitas.');
    end
    if strcmp(modo,'recorte')
        estado.x = min(max(candidato,lb),ub);
    elseif strcmp(modo,'rebote')
        % Evalua exactamente la frontera que se alcanzo, pero devuelve la
        % velocidad hacia dentro para evitar el empuje persistente al exterior.
        fuera = candidato<lb | candidato>ub;
        estado.x = min(max(candidato,lb),ub);
        estado.v(fuera) = -amortiguacion*estado.v(fuera);
    else
        [estado.x,estado.v] = reflejar(candidato,estado.v,lb,ub,amortiguacion);
    end
    costos = nan(n,1);
    for i = 1:n
        costos(i) = evaluar(estado.x(i,:));
    end
    mejora = costos < estado.pbestJ;
    estado.pbest(mejora,:) = estado.x(mejora,:);
    estado.pbestJ(mejora) = costos(mejora);
    [mejor_actual, indice] = min(estado.pbestJ);
    if mejor_actual < estado.mejorJ
        estado.mejorJ = mejor_actual;
        estado.mejorABC = estado.pbest(indice,:);
    end
    estado.iteracion = iteracion;
    estado.historialJ(iteracion+1) = estado.mejorJ;
    estado.historialABC(iteracion+1,:) = estado.mejorABC;
    guardar;
end
resultado = estado;

    function J = evaluar(posicion)
        indice_cache = [];
        if usar_cache && ~isempty(estado.cache_costos)
            indice_cache = find(all(estado.cache_posiciones==posicion,2),1);
        end
        if isempty(indice_cache)
            J = funcion_costo(posicion);
            if ~isnumeric(J) || ~isscalar(J) || ~isreal(J) || ~isfinite(J) || J<0
                error('PSO:CostoInvalido','El costo debe ser un escalar real, finito y no negativo.');
            end
            J = double(J);
            estado.simulaciones_reales = estado.simulaciones_reales+1;
            if usar_cache
                estado.cache_posiciones(end+1,:) = posicion;
                estado.cache_costos(end+1,1) = J;
            end
        else
            J = estado.cache_costos(indice_cache);
            estado.aciertos_cache = estado.aciertos_cache+1;
        end
        estado.evaluaciones = estado.evaluaciones+1;
    end

    function guardar
        estado.estado_aleatorio = flujo.State;
        normalizadas = zeros(n,m);
        libres = rango>0;
        normalizadas(:,libres) = (estado.x(:,libres)-lb(libres))./rango(libres);
        fila = estado.iteracion+1;
        estado.diagnosticos.diversidad_normalizada(fila,:) = std(normalizadas,0,1);
        estado.diagnosticos.fraccion_limite_inferior(fila,:) = mean(estado.x==lb,1);
        estado.diagnosticos.fraccion_limite_superior(fila,:) = mean(estado.x==ub,1);
        estado.diagnosticos.posiciones_unicas(fila) = size(unique(estado.x,'rows'),1);
        estado.diagnosticos.solicitudes_costo(fila) = estado.evaluaciones;
        estado.diagnosticos.simulaciones_reales(fila) = estado.simulaciones_reales;
        estado.diagnosticos.aciertos_cache(fila) = estado.aciertos_cache;
        estado.tiempo_busqueda_segundos = tiempo_anterior+toc(reloj);
        if ~isempty(al_guardar), al_guardar(estado); end
    end
end

function valor = opcion(config,nombre,predeterminado)
if isfield(config,nombre), valor = config.(nombre); else, valor = predeterminado; end
end

function [x,v] = reflejar(candidato,v,lb,ub,amortiguacion)
% Plegado triangular: soporta varios cruces sin bucles ni redondeo de posicion.
% La amortiguacion se aplica a la velocidad por cada frontera cruzada.
x = candidato;
for j = 1:numel(lb)
    ancho = ub(j)-lb(j);
    if ancho==0
        x(:,j) = lb(j); v(:,j) = 0;
        continue;
    end
    fuera = candidato(:,j)<lb(j) | candidato(:,j)>ub(j);
    if ~any(fuera), continue; end
    u = (candidato(fuera,j)-lb(j))/ancho;
    if any(~isfinite(u))
        error('PSO4:Dinamica','El desplazamiento normalizado excede la precision disponible.');
    end
    choques = zeros(size(u));
    altos = u>1;
    choques(altos) = ceil(u(altos))-1;
    choques(~altos) = ceil(-u(~altos));
    x(fuera,j) = lb(j)+ancho*(1-abs(mod(u,2)-1));
    v(fuera,j) = v(fuera,j).*((-amortiguacion).^choques);
end
% Proteccion ante un ulp de error de redondeo en el plegado.
x = min(max(x,lb),ub);
end
