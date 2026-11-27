function [resultado, detalle] = funcion_objetivo_normalizada(senal, referencia, alpha)
%FUNCION_OBJETIVO_NORMALIZADA Costo adimensional de desplazamiento.
% ref = funcion_objetivo_normalizada(acc_pasiva);
% [J, detalle] = funcion_objetivo_normalizada(acc_activa, ref);
% Las variables acc_* de la imagen contienen DESPLAZAMIENTO, en metros.
% Acepta timeseries escalares o una matriz numerica [tiempo desplazamiento].
% La referencia se calcula UNA VEZ y se conserva para todo el experimento.
% J = alpha*ISE/ISE_pasiva + (1-alpha)*pico/pico_pasiva.

alpha_explicito = nargin >= 3 && ~isempty(alpha);
if ~alpha_explicito
    if nargin >= 2 && isstruct(referencia) && isscalar(referencia) && isfield(referencia,'alpha')
        alpha = referencia.alpha;
    else
        alpha = 0.5;
    end
end
validateattributes(alpha, {'numeric'}, ...
    {'real','scalar','finite','>=',0,'<=',1}, mfilename, 'alpha');

if isa(senal, 'timeseries')
    if ~isnumeric(senal.Time) || ~isnumeric(senal.Data) || ...
            ~isreal(senal.Time) || ~isreal(senal.Data)
        error('Objetivo:Datos', 'Se requieren tiempos y desplazamientos numericos reales.');
    end
    t = double(senal.Time(:));
    z = double(senal.Data(:));
elseif isnumeric(senal) && isreal(senal) && ismatrix(senal) && size(senal,2) == 2
    t = double(senal(:,1));
    z = double(senal(:,2));
else
    error('Objetivo:Formato', ...
        'Use una timeseries escalar o una matriz [tiempo desplazamiento].');
end
if numel(t) < 2 || numel(z) ~= numel(t) || ...
        any(~isfinite(t)) || any(~isfinite(z)) || any(diff(t) <= 0)
    error('Objetivo:Datos', ...
        'Se requieren datos finitos, escalares y tiempos estrictamente crecientes.');
end

detalle.ISE = trapz(t, z.^2); % m^2*s; no confundir con sum(z.^2).
detalle.pico = max(abs(z));  % m.
if ~isfinite(detalle.ISE) || ~isfinite(detalle.pico)
    error('Objetivo:Desbordamiento', 'Las metricas no son finitas.');
end

if nargin < 2 || isempty(referencia)
    if detalle.ISE <= 0 || detalle.pico <= 0
        error('Objetivo:ReferenciaNula', ...
            'La respuesta pasiva debe tener ISE y pico positivos.');
    end
    resultado = struct('ISE_pasiva',detalle.ISE, ...
        'pico_pasiva',detalle.pico,'alpha',alpha,'tiempo',t, ...
        'variable','desplazamiento_m','version',1);
    return;
end

required = {'ISE_pasiva','pico_pasiva','alpha','tiempo','variable'};
if ~isstruct(referencia) || ~isscalar(referencia) || ...
        ~all(isfield(referencia,required)) || ...
        ~strcmp(referencia.variable,'desplazamiento_m')
    error('Objetivo:Referencia', 'Referencia de calibracion incompatible.');
end
validateattributes(referencia.ISE_pasiva, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(referencia.pico_pasiva, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(referencia.alpha, {'numeric'}, ...
    {'scalar','real','finite','>=',0,'<=',1});
if alpha_explicito && alpha ~= referencia.alpha
    error('Objetivo:Peso', 'El peso debe ser el fijado en la calibracion.');
end
tref = referencia.tiempo(:);
if ~isnumeric(tref) || ~isreal(tref) || numel(tref) < 2 || ...
        numel(t) ~= numel(tref) || any(~isfinite(tref)) || any(diff(tref) <= 0) || ...
        any(abs(t-tref) > 1e-10 * max(1,max(abs(tref))))
    error('Objetivo:Ventana', ...
        'Use la misma ventana y malla temporal de la calibracion.');
end
detalle.ISE_normalizado = detalle.ISE / referencia.ISE_pasiva;
detalle.pico_normalizado = detalle.pico / referencia.pico_pasiva;
detalle.alpha = referencia.alpha;
resultado = referencia.alpha * detalle.ISE_normalizado + ...
    (1-referencia.alpha) * detalle.pico_normalizado;
if ~isfinite(resultado)
    error('Objetivo:Costo', 'El costo normalizado no es finito.');
end
end
