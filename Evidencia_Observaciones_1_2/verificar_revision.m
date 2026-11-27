function verificar_revision(raiz,reutilizar)
% Verificacion de registros y sensibilidad PIDF para la segunda revision.
% No altera los modelos ni los registros originales. No repite las 30 busquedas.
if nargin==0, raiz=fileparts(mfilename('fullpath')); end
if nargin<2,reutilizar=false;end
base=raiz;
destPSO=fullfile(raiz,'02_PSO','auditoria'); if ~isfolder(destPSO),mkdir(destPSO);end
dest=fullfile(raiz,'01_PIDF','resultados'); if ~isfolder(dest),mkdir(dest);end
diary(fullfile(dest,'verificacion_revision.log')); fin=onCleanup(@() diary('off'));
fprintf('Verificacion nueva: %s; MATLAB %s\n',datestr(now,30),version);
camp=fullfile(base,'02_PSO');
T=readtable(fullfile(camp,'resumen','resultados_ejecuciones.csv'));
assert(height(T)==30 && isequal(sort(T.Semilla),(1:30)'));
errores=zeros(30,4); ventanas=zeros(30,3);
for k=1:30
 d=load(fullfile(camp,'ejecuciones',sprintf('ejecucion_%02d',k),'ejecucion_01.mat'));
 r=d.registro; s=d.senales_validacion; ref=d.referencia_objetivo;
 assert(strcmp(r.estado,'completada') && r.semilla==T.Semilla(k));
 assert(r.evaluaciones==1020 && numel(r.historialJ)==51);
 assert(all(diff(r.historialJ)<=1e-12));
 t=s.tiempo(:); z=s.desplazamiento_activo(:); zp=s.desplazamiento_pasivo(:);
 j=.5*trapz(t,z.^2)/ref.ISE_pasiva+.5*max(abs(z))/ref.pico_pasiva;
 errores(k,:)=[r.mejorJ-T.CostoFinal(k),max(abs(r.mejorABC-[T.A(k),T.B(k),T.C(k)])),j-T.CostoFinal(k),(.5*trapz(t,zp.^2)/ref.ISE_pasiva+.5*max(abs(zp))/ref.pico_pasiva)-1];
 ventanas(k,:)=[t(1),t(end),numel(t)];
 assert(max(abs(errores(k,1:2)))<1e-9 && abs(errores(k,3))<1e-6);
end
[best,idx]=min(T.CostoFinal); assert(T.Semilla(idx)==24);
auditoria=table(T.Semilla,errores(:,1),errores(:,2),errores(:,3),errores(:,4),ventanas(:,1),ventanas(:,2),ventanas(:,3), ...
 'VariableNames',{'Semilla','DeltaCostoMAT_CSV','DeltaABC','DeltaTrapz_Costo','DeltaJPasivo','Inicio_s','Final_s','Muestras'});
writetable(auditoria,fullfile(destPSO,'auditoria_30_registros.csv'));
writetable(T,fullfile(destPSO,'resultados_30_ejecuciones_verificados.csv'));
stats=table(height(T),mean(T.CostoFinal),std(T.CostoFinal),median(T.CostoFinal),best,max(T.CostoFinal),T.Semilla(idx),T.A(idx),T.B(idx),T.C(idx),...
 'VariableNames',{'N','Media','DesvMuestral','Mediana','Mejor','Peor','SemillaMejor','A','B','C'});
writetable(stats,fullfile(destPSO,'estadisticos_verificados.csv'));disp(stats);
fprintf('Max diferencia trapz vs objetivo Simulink: %.12g\n',max(abs(errores(:,3))));

ctrl=fullfile(base,'01_PIDF','modelo_original');
datosP=load(fullfile(ctrl,'resultados_pulso_20261112_043616_465','datos_y_metricas.mat'));
datosE=load(fullfile(ctrl,'resultados_estocastico_20261112_043955_729','datos_y_metricas.mat'));
ref=load(fullfile(camp,'fuentes','referencia_objetivo_normalizado.mat'));ref=ref.referencia_objetivo;
Iref=ref.ISE_pasiva;Pref=ref.pico_pasiva;
for d={datosP,datosE}
 x=d{1};writematrix([x.t,x.zr,x.Z,x.U],fullfile(dest,['series_originales_' x.escenario '.csv']));
end

% Copia de trabajo: para los barridos se comenta solo la inferencia FLC.
% Las ramas PID y pasiva, el solver y las fuentes se conservan.
mdl='Modelo_revision2'; mf=fullfile(dest,[mdl '.slx']);
if bdIsLoaded(mdl),close_system(mdl,0);end
copyfile(fullfile(ctrl,'ActiveSuspensionv2.slx'),mf);
prev=pwd;cd(dest);cleanupDir=onCleanup(@() cd(prev));
copyfile(fullfile(ctrl,'suspension.fis'),fullfile(dest,'suspension.fis'));
load_system(mf);cleanupModel=onCleanup(@() close_system(mdl,0));
pb=[mdl '/PID Controller'];sw=[mdl '/Manual Switch'];
fb=find_system(mdl,'SearchDepth',1,'MaskType','Fuzzy Logic Controller');
if isempty(fb),bb=find_system(mdl,'SearchDepth',1,'Type','Block');fb=bb(contains(bb,'Fuzzy'));end
assert(numel(fb)==1);
set_param(mdl,'SimulationMode','normal','Solver','ode3','FixedStep','0.001','StartTime','0','StopTime','10','ReturnWorkspaceOutputs','on');
phys=struct('M2',250,'M1',50,'K2',16000,'B2',1500,'K1',160000,'B1',0,'A',T.A(idx),'B',T.B(idx),'C',T.C(idx),'Ts',10);
Ap=[0 1 0 0;-64 -6 64 6;0 0 0 1;320 30 -3520 -30];Bp=[0;1/250;0;-1/50];
plant=ss(Ap,Bp,[1 0 0 0],0);opts=pidtuneOptions('DesignFocus','disturbance-rejection');
C0=pidtune(plant,'PID',15,opts);g0=[C0.Kp,C0.Ki,C0.Kd,100];
fprintf('PID original: %.12g %.12g %.12g N=%.12g\n',g0);
% Validacion previa de las dos ramas activas contra las series originales.
baseline=cell(2,1);checks=zeros(2,4);
for e=1:2
 guardado=fullfile(dest,sprintf('reproduccion_escenario_%d.mat',e));
 if reutilizar && isfile(guardado),previo=load(guardado,'s');s=previo.s;else,s=simular(g0,e,false);end
 baseline{e}=s; original={datosP,datosE};original=original{e};
 checks(e,:)=[max(abs(s.Z(:,1)-original.Z(:,1))),max(abs(s.Z(:,2)-original.Z(:,2))),max(abs(s.Z(:,3)-original.Z(:,3))),max(abs(s.U(:,2:3)-original.U(:,2:3)),[],'all')];
 fprintf('Escenario %d; diferencias pasivo/FLC/PID/fuerza: %.9g %.9g %.9g %.9g\n',e,checks(e,:));
 save(fullfile(dest,sprintf('reproduccion_escenario_%d.mat',e)),'s','original','checks');
 assert(max(checks(e,1:3))<2e-5 && checks(e,4)<2, 'Las series originales no coinciden: detener y revisar antes de comparar.');
end
writematrix(checks,fullfile(dest,'errores_reproduccion.csv'));

% Barrido predeterminado de cruces y filtros; criterio de seleccion J del pulso.
wcList=[10 12 15 18 20 22 25];nList=[50 100 200];
G=[];W=[];Clase=strings(0,1);
for wc=wcList
 cc=pidtune(plant,'PID',wc,opts);
 for nf=nList,G(end+1,:)=[cc.Kp cc.Ki cc.Kd nf];W(end+1,1)=wc;Clase(end+1,1)="pidtune";end
end
R=table();trazas={};
for k=1:size(G,1),evaluar(k);end
valid=find(R.EstabilidadLineal & isfinite(R.J_pulso));[~,ii]=min(R.J_pulso(valid)); ib=valid(ii);
centro=G(ib,:);wcCentro=W(ib);
% Refinamiento local de +/-20% en las tres ganancias, con N seleccionado fijo.
for fp=[.8 1 1.2],for fi=[.8 1 1.2],for fd=[.8 1 1.2]
 g=centro.*[fp fi fd 1];if any(all(abs(G-g)<1e-9,2)),continue;end
 G(end+1,:)=g;W(end+1,1)=wcCentro;Clase(end+1,1)="refinamiento20pct";evaluar(size(G,1));
end,end,end
valid=find(R.EstabilidadLineal & isfinite(R.J_pulso));[~,ii]=min(R.J_pulso(valid)); ib=valid(ii);
seleccion=R(ib,:);disp(seleccion);writetable(seleccion,fullfile(dest,'pid_seleccionado.csv'));
save(fullfile(dest,'sensibilidad_pid.mat'),'R','G','W','Clase','trazas','ib','baseline','Iref','Pref','checks');
% La copia entregable conserva las tres ramas activas y carga ganancias elegidas.
set_param(fb{1},'Commented','off');set_param(sw,'sw','1');
mw=get_param(mdl,'ModelWorkspace'); f=fieldnames(phys);for j=1:numel(f),assignin(mw,f{j},phys.(f{j}));end
assignin(mw,'Kp',G(ib,1));assignin(mw,'Ki',G(ib,2));assignin(mw,'Kd',G(ib,3));set_param(pb,'N',num2str(G(ib,4),17));
save_system(mdl,mf);
fprintf('VERIFICACION COMPLETADA; candidato elegido %d de %d.\n',ib,height(R));

 function evaluar(k)
  g=G(k,:); stable=isstable(feedback(pid(g(1),g(2),g(3),1/g(4))*plant,1));
  v=nan(1,12);
  if stable
   sp=simular(g,1,true);se=simular(g,2,true);trazas{k}={sp,se};
   v=[metricas(sp),metricas(se)];
  end
  row=table(k,Clase(k),W(k),g(1),g(2),g(3),g(4),stable,v(1),v(2),v(3),v(4),v(5),v(6),v(7),v(8),v(9),v(10),v(11),v(12),...
   'VariableNames',{'Candidato','Familia','wc_origen','Kp','Ki','Kd','N','EstabilidadLineal','J_pulso','RMS_pulso','Pico_pulso','FRMS_pulso','Fpico_pulso','IF_pulso','J_estocastico_refPulso','RMS_estocastico','Pico_estocastico','FRMS_estocastico','Fpico_estocastico','IF_estocastico'});
  R=[R;row];writetable(R,fullfile(dest,'sensibilidad_pid.csv'));
  fprintf('Candidato %d: J %.8f RMS %.8f pico %.8f\n',k,v(1:3));
 end
 function vals=metricas(s)
  iz=trapz(s.t,s.Z(:,3).^2);pk=max(abs(s.Z(:,3)));iff=trapz(s.t,s.U(:,3).^2);
  assert(max(abs(s.U(:,3)))<=5000+1e-6);
  vals=[.5*iz/Iref+.5*pk/Pref,sqrt(iz/10),pk,sqrt(iff/10),max(abs(s.U(:,3))),iff];
 end
 function s=simular(g,esc,omitirFLC)
  if omitirFLC,set_param(fb{1},'Commented','on');else,set_param(fb{1},'Commented','off');end
  set_param(sw,'sw',num2str(2-esc));
  si=Simulink.SimulationInput(mdl); f=fieldnames(phys);for j=1:numel(f),si=si.setVariable(f{j},phys.(f{j}));end
  si=si.setVariable('Kp',g(1)).setVariable('Ki',g(2)).setVariable('Kd',g(3));si=si.setBlockParameter(pb,'N',num2str(g(4),17));
  oo=sim(si); a=oo.get('dsp_pasiva');b=oo.get('dsp_activa_FLC');c=oo.get('dsp_activa_PID');u=oo.get('force_FLC');v=oo.get('force_PID');
  if omitirFLC,zf=nan(numel(a.Time),1);uf=zf;else,zf=b.Data(:);uf=u.Data(:);end
  s=struct('t',double(a.Time(:)),'Z',[a.Data(:),zf,c.Data(:)],'U',[zeros(numel(a.Time),1),uf,v.Data(:)]);
  assert(numel(s.t)==10001 && all(isfinite(s.Z(:,[1 3])),'all'));
 end
end
