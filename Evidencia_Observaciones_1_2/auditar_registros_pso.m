function resumen=auditar_registros_pso(carpeta,salida)
% Recalcula las 30 validaciones archivadas; no ejecuta nuevas busquedas.
if nargin<1,carpeta=fullfile(fileparts(mfilename('fullpath')),'02_PSO');end
if nargin<2,salida=fullfile(fileparts(mfilename('fullpath')),'02_PSO','auditoria_nueva');end
if ~isfolder(salida),mkdir(salida);end
T=readtable(fullfile(carpeta,'resumen','resultados_ejecuciones.csv'));
assert(height(T)==30 && isequal(sort(T.Semilla),(1:30)'));
delta=zeros(30,4);ventana=zeros(30,3);
for k=1:30
 D=load(fullfile(carpeta,'ejecuciones',sprintf('ejecucion_%02d',k),'ejecucion_01.mat'));
 r=D.registro;s=D.senales_validacion;ref=D.referencia_objetivo;
 assert(strcmp(r.estado,'completada') && r.semilla==T.Semilla(k));
 assert(r.evaluaciones==1020 && numel(r.historialJ)==51 && all(diff(r.historialJ)<=1e-12));
 t=s.tiempo(:);z=s.desplazamiento_activo(:);zp=s.desplazamiento_pasivo(:);
 j=.5*trapz(t,z.^2)/ref.ISE_pasiva+.5*max(abs(z))/ref.pico_pasiva;
 jp=.5*trapz(t,zp.^2)/ref.ISE_pasiva+.5*max(abs(zp))/ref.pico_pasiva;
 delta(k,:)=[r.mejorJ-T.CostoFinal(k),max(abs(r.mejorABC-[T.A(k),T.B(k),T.C(k)])),j-T.CostoFinal(k),jp-1];
 ventana(k,:)=[t(1),t(end),numel(t)];
 assert(max(abs(delta(k,1:2)))<1e-9 && abs(delta(k,3))<1e-6);
end
[mejor,idx]=min(T.CostoFinal);
resumen=table(30,mean(T.CostoFinal),std(T.CostoFinal),median(T.CostoFinal),mejor,max(T.CostoFinal),T.Semilla(idx),T.A(idx),T.B(idx),T.C(idx), ...
 'VariableNames',{'N','Media','DesvMuestral','Mediana','Mejor','Peor','SemillaMejor','A','B','C'});
assert(T.Semilla(idx)==24);
writetable(resumen,fullfile(salida,'estadisticos_verificados.csv'));
writetable(T,fullfile(salida,'resultados_30_ejecuciones_verificados.csv'));
writematrix([T.Semilla,delta,ventana],fullfile(salida,'auditoria_por_semilla.csv'));
disp(resumen);fprintf('Max diferencia entre trapz y costo registrado: %.12g\n',max(abs(delta(:,3))));
fprintf('Ventana de la campana: %.3f a %.3f s; %d muestras.\n',ventana(1,:));
end
