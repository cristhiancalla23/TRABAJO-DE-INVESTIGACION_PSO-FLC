function manifest = manifest_pso4(carpeta)
% Bytes originales, con nombres relativos al proyecto. No depende de PSO 3.
archivos = [dir(fullfile(carpeta,'*.m')); dir(fullfile(carpeta,'*.slx')); ...
    dir(fullfile(carpeta,'*.fis'))];
nombres = sort([{archivos.name}, {'referencia_objetivo_normalizado.mat', ...
    'referencia_calibrada_origen.mat'}]);
manifest = cell(numel(nombres),1);
for k = 1:numel(nombres)
    fid = fopen(fullfile(carpeta,nombres{k}),'rb');
    if fid < 0, error('PSO4:Fuente','No se puede leer %s.',nombres{k}); end
    cierre = onCleanup(@() fclose(fid));
    contenido = fread(fid,Inf,'*uint8');
    manifest{k} = struct('nombre',nombres{k},'contenido',contenido);
    clear cierre;
end
end
