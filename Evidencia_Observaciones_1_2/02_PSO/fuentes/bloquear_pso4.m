function liberar = bloquear_pso4(archivo)
% Bloqueo de archivo del sistema operativo; se libera al cerrar MATLAB.
% El archivo puede permanecer en disco: su existencia NO significa bloqueo.
% Windows: FileShare.None funciona tambien en sesiones MATLAB sin JVM.
if ispc && NET.isNETSupported
    try
        flujo = System.IO.File.Open(char(archivo),System.IO.FileMode.OpenOrCreate, ...
            System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
    catch ME
        error('PSO4:Ocupado', ...
            ['No se pudo obtener acceso exclusivo a %s. Puede estar ocupado ' ...
            'o no tener permisos. Detalle original: %s'],archivo,ME.message);
    end
    liberar = onCleanup(@() cerrar_dotnet(flujo));
    return;
end
% Alternativa para entornos donde Java este disponible.
assert(usejava('jvm'),'PSO4:RuntimeBloqueo', ...
    'No hay un runtime .NET compatible en Windows ni una JVM para el bloqueo.');
flujo = javaObject('java.io.RandomAccessFile',archivo,'rw');
canal = flujo.getChannel();
try
    bloqueo = canal.tryLock();
catch ME
    canal.close(); flujo.close();
    error('PSO4:Ocupado','Otra tarea utiliza %s. Detalle: %s',archivo,ME.message);
end
if isempty(bloqueo)
    canal.close(); flujo.close();
    error('PSO4:Ocupado','Otra tarea utiliza %s. Espere a que termine o pause.',archivo);
end
liberar = onCleanup(@() cerrar(bloqueo,canal,flujo));
end

function cerrar_dotnet(flujo)
try, flujo.Dispose(); catch, end
end

function cerrar(bloqueo,canal,flujo)
try, if bloqueo.isValid(), bloqueo.release(); end, catch, end
try, canal.close(); catch, end
try, flujo.close(); catch, end
end
