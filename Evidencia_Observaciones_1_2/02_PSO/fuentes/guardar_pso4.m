function guardar_pso4(archivo, nombre, valor)
% Escritura atomica: conserva el ultimo MAT completo si se interrumpe el save.
datos = struct; datos.(nombre) = valor;
temporal = [archivo '.tmp.mat'];
save(temporal,'-struct','datos','-v7');
[ok,mensaje] = movefile(temporal,archivo,'f');
if ~ok, error('PSO4:Guardado','No se pudo guardar %s: %s',archivo,mensaje); end
end
