function finalizar_revision(raiz)
if nargin==0,raiz=fileparts(mfilename('fullpath'));end
d=fullfile(raiz,'01_PIDF','resultados');s=load(fullfile(d,'sensibilidad_pid.mat'));
R=s.R;ib=s.ib;summary=struct;summary.seleccion=table2struct(R(ib,:));summary.total=height(R);
summary.stats=table2struct(readtable(fullfile(raiz,'02_PSO','auditoria','estadisticos_verificados.csv')));
summary.errores_reproduccion=s.checks;
orig=find(abs(R.wc_origen-15)<1e-12 & R.N==100 & R.Familia=="pidtune");assert(isscalar(orig));
summary.error_ramas_independientes=zeros(2,2);
for e=1:2
 b=s.baseline{e};p=s.trazas{ib}{e};p0=s.trazas{orig}{e};t=b.t;
 summary.error_ramas_independientes(e,:)=[max(abs(p0.Z(:,3)-b.Z(:,3))),max(abs(p0.U(:,3)-b.U(:,3)))];
 assert(max(summary.error_ramas_independientes(e,:))<1e-8);
 Z=[b.Z,p.Z(:,3)];U=[b.U,p.U(:,3)];
 names=["Pasivo";"PSO-FLC";"PIDF0";"PIDFr"];
 ise=trapz(t,Z.^2)';pk=max(abs(Z))';fr=sqrt(trapz(t,U.^2)'/10);fp=max(abs(U))';iff=trapz(t,U.^2)';zrms=sqrt(ise/10);
 j=.5*ise/s.Iref+.5*pk/s.Pref;v=t<=5;
 j5=.5*trapz(t(v),Z(v,:).^2)'/s.Iref+.5*max(abs(Z(v,:)))'/s.Pref;
 tab=table(names,zrms,pk,ise,100*(1-zrms/zrms(1)),100*(1-pk/pk(1)),fr,fp,iff,j,j5,...
  'VariableNames',{'Sistema','RMS_m','Pico_m','ISE_m2s','ReduccionRMS_pct','ReduccionPico_pct','FRMS_N','Fpico_N','IF_N2s','J10_refPulso','J5_refPulso'});
 escs={'pulso','estocastico'};esc=escs{e};
 writetable(tab,fullfile(d,['comparacion_final_' esc '.csv']));
 writematrix([t,Z,U],fullfile(d,['series_finales_' esc '.csv']));
 summary.(esc)=table2struct(tab);
 summary.(['FLC_vs_PIDFr_' esc])=[100*(1-zrms(2)/zrms(4)),100*(1-pk(2)/pk(4)),100*(fr(2)/fr(4)-1)];
 for f=1:2
  fig=figure('Visible','off','Color','w','Units','centimeters','Position',[2 2 17.5 8]);
  if f==1,Y=Z;ylabelText='Desplazamiento del chasis (m)';fname=['fig_desplazamiento_' esc];else,Y=U(:,2:4);ylabelText='Fuerza del actuador (N)';fname=['fig_fuerza_actuador_' esc];end
  ax=axes(fig);hold(ax,'on');
  if f==1
   plot(t,Y(:,1),'--','Color',[.4 .4 .4],'LineWidth',1);plot(t,Y(:,2),'Color',[0 .35 .7],'LineWidth',1.1);plot(t,Y(:,3),':','Color',[.8 .25 0],'LineWidth',1);plot(t,Y(:,4),'Color',[.15 .55 .25],'LineWidth',1.1);
   legend(names,'Location','northeast','Orientation','horizontal','FontSize',8);
  else
   plot(t,Y(:,1),'Color',[0 .35 .7],'LineWidth',1.1);plot(t,Y(:,2),':','Color',[.8 .25 0],'LineWidth',1);plot(t,Y(:,3),'Color',[.15 .55 .25],'LineWidth',1.1);
   yline(5000,'--k','HandleVisibility','off');yline(-5000,'--k','HandleVisibility','off');ylim([-5500 5500]);legend(names(2:4),'Location','northeast','Orientation','horizontal','FontSize',8);
  end
  grid on;xlim([0 10]);xlabel('Tiempo (s)');ylabel(ylabelText);set(ax,'FontName','Arial','FontSize',10);
  exportgraphics(fig,fullfile(d,[fname '.pdf']),'ContentType','vector');exportgraphics(fig,fullfile(d,[fname '.png']),'Resolution',180);close(fig);
 end
end
Ap=[0 1 0 0;-64 -6 64 6;0 0 0 1;320 30 -3520 -30];Bp=[0;1/250;0;-1/50];P=ss(Ap,Bp,[1 0 0 0],0);g=s.G(ib,:);
[gm,pm,wcg,wcp]=margin(pid(g(1),g(2),g(3),1/g(4))*P);summary.margenes_lineales=struct('GM',gm,'PM_deg',pm,'Wcg',wcg,'Wcp',wcp);
summary.matlab=version;summary.fecha=datestr(now,30);
fid=fopen(fullfile(d,'resumen_final.json'),'w','n','UTF-8');fprintf(fid,'%s',jsonencode(summary,PrettyPrint=true));fclose(fid);
disp(summary);fprintf('EXPORTACION FINAL COMPLETADA\n');
end
