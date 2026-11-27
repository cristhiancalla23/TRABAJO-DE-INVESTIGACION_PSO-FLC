function probar_bloqueo_pso4
% Prueba de exclusion y liberacion real; no ejecuta Simulink ni crea un pool.
archivo = [tempname(tempdir) '.lock'];
limpiar = onCleanup(@() retirar_archivo(archivo)); %#ok<NASGU>
primero = bloquear_pso4(archivo);
ocupado = false;
try
    segundo = bloquear_pso4(archivo); %#ok<NASGU>
catch ME
    assert(strcmp(ME.identifier,'PSO4:Ocupado'), ...
        'PSO4Prueba:Bloqueo','Fallo inesperado: %s',ME.message);
    ocupado = true;
end
assert(ocupado,'PSO4Prueba:Bloqueo','Dos escritores consiguieron el mismo bloqueo.');
clear primero;
% El archivo aun existe, pero el bloqueo del sistema ya se ha liberado.
assert(isfile(archivo));
tercero = bloquear_pso4(archivo);
clear tercero;
% Comprobar liberacion automatica al salir con una excepcion.
try
    salir_con_error(archivo);
catch ME
    assert(strcmp(ME.identifier,'PSO4Prueba:SalidaControlada'));
end
cuarto = bloquear_pso4(archivo);
clear cuarto;
fprintf('PRUEBA DE BLOQUEO CORRECTA: exclusion, liberacion y reutilizacion.\n');
end

function salir_con_error(archivo)
temporal = bloquear_pso4(archivo); %#ok<NASGU>
error('PSO4Prueba:SalidaControlada','Excepcion deliberada para probar la limpieza.');
end

function retirar_archivo(archivo)
try
    if isfile(archivo), delete(archivo); end
catch
    % Si otra incidencia mantiene el bloqueo, conservar el archivo temporal.
end
end
